// owner_home_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'api_service.dart';
import 'login_screen.dart'; // Or owner_login_screen.dart depending on what you named it
import 'owner/owner_availability_screen.dart';
import 'owner/owner_slot_map_screen.dart';
import 'owner/owner_walkin_screen.dart';
import 'owner_booking_screen.dart';
import 'owner_money_screen.dart';
import 'owner_more_screen.dart';
import 'owner_parking_screen.dart';
import 'owner_support_screen.dart';
import 'kyc_screen.dart';


class _Palette {
  static const Color ink = Color(0xFF0A0A0A);
  static const Color inkSoft = Color(0xFF1F2937);
  static const Color accent = Color(0xFF2F6FED); // electric blue
  static const Color accentDeep = Color(0xFF1849B8);
  static const Color success = Color(0xFF17A673);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color bg = Color(0xFFF5F6F8);
  static const Color card = Colors.white;
  static const Color muted = Color(0xFF6B7280);
  static const Color hairline = Color(0xFFE9EAEE);
}

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({Key? key}) : super(key: key);

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = {};
  List<dynamic> _recentBookings = [];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  String _userName = 'User';
  String _userEmail = '';
  // roleId is guaranteed to be 3 for owner, but kept for session consistency
  String _roleId = '3';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
    _initSessionAndData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initSessionAndData() async {
    final session = await ApiService.getUserSession();
    if (mounted) {
      setState(() {
        _roleId = session['roleId']?.toString() ?? '3';
        _userName = session['fullName']?.toString() ?? 'Owner';
        _userEmail = session['email']?.toString() ?? '';
      });
    }
    await _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      // Kept exact same API logic
      final responses = await Future.wait([
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=bookings')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=parking_spaces')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=parking_space_owners')),
      ]);

      if (mounted) {
        List<dynamic> allBookings = [];
        List<dynamic> allParkings = [];
        List<dynamic> allOwners = [];

        if (responses[0].statusCode == 200) {
          final bData = json.decode(responses[0].body);
          if (bData['status'] == true) allBookings = bData['data'] ?? [];
        }
        if (responses[1].statusCode == 200) {
          final pData = json.decode(responses[1].body);
          if (pData['status'] == true) allParkings = pData['data'] ?? [];
        }
        if (responses[2].statusCode == 200) {
          final oData = json.decode(responses[2].body);
          if (oData['status'] == true) allOwners = oData['data'] ?? [];
        }

        List<dynamic> targetBookings = [];
        List<dynamic> targetParkings = [];

        // --- FILTER FOR PARKING OWNER ONLY ---
        String? currentOwnerId;
        for (var owner in allOwners) {
          if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase()) {
            currentOwnerId = owner['id'].toString();
            break;
          }
        }

        if (currentOwnerId != null) {
          targetParkings = allParkings.where((p) => p['owner_id'].toString() == currentOwnerId).toList();
          List<String> ownedParkingIds = targetParkings.map((p) => p['id'].toString()).toList();
          targetBookings = allBookings.where((b) => ownedParkingIds.contains(b['parking_id'].toString())).toList();
        }

        // --- CALCULATE STATS ---
        int totalBookings = targetBookings.length;
        int confirmedBookings = 0;
        int pendingBookings = 0;
        double totalRevenue = 0.0;
        List<double> monthlyBookings = List.filled(12, 0.0);
        List<double> monthlyRevenue = List.filled(12, 0.0);

        for (var booking in targetBookings) {
          final status = booking['status']?.toString().toLowerCase() ?? '';
          if (status == 'confirmed') confirmedBookings++;
          if (status == 'pending') pendingBookings++;

          double amount = double.tryParse(booking['total_amount']?.toString() ?? '0') ?? 0;
          totalRevenue += amount;

          try {
            DateTime bookingDate = DateTime.parse(booking['booking_date'] ?? '');
            int monthIndex = bookingDate.month - 1;
            monthlyBookings[monthIndex] = (monthlyBookings[monthIndex] ?? 0) + 1;
            monthlyRevenue[monthIndex] = (monthlyRevenue[monthIndex] ?? 0) + amount;
          } catch (e) {
            debugPrint('Date parsing error: $e');
          }
        }

        int totalParkings = targetParkings.length;
        int approvedParkings = 0;
        int pendingParkings = 0;

        for (var space in targetParkings) {
          final status = space['status']?.toString().toLowerCase() ?? '';
          if (status == 'approved') approvedParkings++;
          if (status == 'pending') pendingParkings++;
        }

        setState(() {
          _dashboardData = {
            'totalParkings': totalParkings,
            'approvedParkings': approvedParkings,
            'pendingParkings': pendingParkings,
            'totalBookings': totalBookings,
            'confirmedBookings': confirmedBookings,
            'pendingBookings': pendingBookings,
            'totalRevenue': totalRevenue,
            'monthlyBookings': monthlyBookings,
            'monthlyRevenue': monthlyRevenue,
            'rating': '4.8', // Kept static as per original code
          };
          _recentBookings = targetBookings.take(5).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading dashboard: ${e.toString()}'),
            backgroundColor: _Palette.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    await ApiService.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const OwnerLoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      extendBodyBehindAppBar: false,
      appBar: _buildAppBar(),
      bottomNavigationBar: _buildOwnerBottomBar(), // Directly builds Owner Bar
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: _Palette.accent,
            backgroundColor: Colors.white,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeSection(),
                    const SizedBox(height: 20),
                    _buildOwnerSubStats(),
                    const SizedBox(height: 24),
                    _buildActionCards(),
                    _buildStatsGrid(),
                    const SizedBox(height: 24),
                    _buildChartsSection(),
                    const SizedBox(height: 24),
                    _buildRecentBookings(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),

          if (_isLoading)
            const Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: _Palette.accent,
                minHeight: 3,
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_Palette.ink, _Palette.inkSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: _Palette.ink.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.local_parking_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text(
            'Park Hub',
            style: TextStyle(color: _Palette.ink, fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: -0.4),
          ),
        ],
      ),
      actions: [
        _appBarIconButton(Icons.notifications_none_rounded, () {}, showDot: true),
        const SizedBox(width: 4),
        _appBarIconButton(Icons.logout_rounded, _handleLogout),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _appBarIconButton(IconData icon, VoidCallback onTap, {bool showDot = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _Palette.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: Icon(icon, color: _Palette.ink, size: 21),
            onPressed: onTap,
            splashRadius: 22,
          ),
        ),
        if (showDot)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _Palette.danger,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOwnerBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(Icons.home_rounded, 'Home', () {}, isActive: true),
              _buildBottomNavItem(
                Icons.calendar_today_rounded,
                'Bookings',
                    () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OwnerBookingScreen())),
              ),
              _buildBottomNavItem(
                Icons.local_parking_rounded,
                'Parking',
                    () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OwnerParkingScreen())),
              ),
              _buildBottomNavItem(
                Icons.account_balance_wallet_rounded,
                'Money',
                    () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OwnerMoneyScreen())),
              ),
              _buildBottomNavItem(
                Icons.more_horiz_rounded,
                'More',
                    () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OwnerMoreScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) {
    final color = isActive ? _Palette.accent : _Palette.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          // Wrapped in SingleChildScrollView to prevent overflow on small height bottom bars
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isActive ? _Palette.accent.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    final now = DateTime.now();
    final dateString = DateFormat('EEEE, d MMM yyyy').format(now);
    final initial = _userName.trim().isNotEmpty ? _userName.trim()[0].toUpperCase() : 'O';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_Palette.ink, _Palette.inkSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: _Palette.ink.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userName,
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 11),
                    const SizedBox(width: 6),
                    Text(dateString, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Here's what's happening with your parking spaces today.",
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13, fontWeight: FontWeight.w400, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerSubStats() {
    return Row(
      children: [
        Expanded(child: _buildSubStatCard('Pending Parkings', _dashboardData['pendingParkings']?.toString() ?? '0', Icons.hourglass_top_rounded, _Palette.warning)),
        const SizedBox(width: 12),
        Expanded(child: _buildSubStatCard('Pending Bookings', _dashboardData['pendingBookings']?.toString() ?? '0', Icons.assignment_rounded, _Palette.warning)),
        const SizedBox(width: 12),
        Expanded(child: _buildSubStatCard('Rating', _dashboardData['rating']?.toString() ?? '0.0', Icons.star_rounded, Colors.amber.shade700)),
      ],
    );
  }

  Widget _buildSubStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: _Palette.ink, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: _Palette.muted, fontSize: 11.5, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildActionCards() {
    List<Map<String, dynamic>> cards = [
      {'title': 'KYC', 'subtitle': 'Documents', 'icon': Icons.verified_user_rounded, 'color': Colors.blue, 'screen': const KycScreen()},
      {'title': 'Support', 'subtitle': 'Tickets & Chat', 'icon': Icons.support_agent_rounded, 'color': Colors.teal, 'screen': const OwnerSupportScreen()},
      {'title': 'Availability', 'subtitle': 'Open / Full / Closed', 'icon': Icons.toggle_on_rounded, 'color': Colors.orange, 'screen': const OwnerAvailabilityScreen()},
      {'title': 'Slot Map', 'subtitle': 'Visual slots', 'icon': Icons.grid_view_rounded, 'color': Colors.indigo, 'screen': const OwnerSlotMapScreen()},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.3)),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.of(context).size.width < 600 ? 2 : 3,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.6,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index];
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                if (card['screen'] != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => card['screen']));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${card['title']} feature coming soon!'),
                      backgroundColor: _Palette.warning,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(12),
                    ),
                  );
                }
              },
              child: _buildActionCard(
                title: card['title'] as String,
                subtitle: card['subtitle'] as String?,
                icon: card['icon'] as IconData,
                color: card['color'] as MaterialColor,
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required MaterialColor color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      // Wrapped in SingleChildScrollView to prevent GridView bottom overflow on tiny screens
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color.shade600, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: _Palette.ink,
                letterSpacing: -0.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: _Palette.muted,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    List<Map<String, dynamic>> stats = [
      {'title': 'Total Parkings', 'value': _dashboardData['totalParkings'] ?? 0, 'subtitle': '↑ ${_dashboardData['approvedParkings'] ?? 0} Active', 'icon': Icons.local_parking_rounded, 'color': _Palette.accent},
      {'title': 'Total Bookings', 'value': _dashboardData['totalBookings'] ?? 0, 'subtitle': '↑ ${_dashboardData['confirmedBookings'] ?? 0} Confirmed', 'icon': Icons.calendar_month_rounded, 'color': _Palette.accent},
      {'title': 'Average Rating', 'value': _dashboardData['rating'] ?? '0.0', 'subtitle': '★ Based on reviews', 'icon': Icons.star_rounded, 'color': Colors.amber.shade700},
      {'title': 'Total Revenue', 'value': '₹${(_dashboardData['totalRevenue'] ?? 0).toStringAsFixed(0)}', 'subtitle': '↑ Lifetime Earnings', 'icon': Icons.monetization_on_rounded, 'color': _Palette.warning},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.95,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _Palette.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          // ScrollView to combat strict childAspectRatio bottom overflows
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: (stat['color'] as Color).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(stat['icon'] as IconData, color: stat['color'] as Color, size: 20),
                ),
                const SizedBox(height: 16), // Replaced Spacer() for layout stability inside ScrollView
                Text(stat['value'].toString(), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: _Palette.ink, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(stat['title'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _Palette.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _Palette.success.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
                  child: Text(stat['subtitle'].toString(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _Palette.success), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChartsSection() {
    List<dynamic> monthlyBookingsData = _dashboardData['monthlyBookings'] ?? [];
    List<dynamic> monthlyRevenueData = _dashboardData['monthlyRevenue'] ?? [];

    List<double> bookingsData = monthlyBookingsData.map((e) => (e as num).toDouble()).toList();
    List<double> revenueData = monthlyRevenueData.map((e) => (e as num).toDouble()).toList();

    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Column(
        children: [
          _buildChartContainer('Monthly Bookings', Icons.bar_chart_rounded, bookingsData, _Palette.accent, false),
          const SizedBox(height: 16),
          _buildChartContainer('Monthly Revenue', Icons.monetization_on_rounded, revenueData, _Palette.success, true),
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(child: _buildChartContainer('Monthly Bookings', Icons.bar_chart_rounded, bookingsData, _Palette.accent, false)),
          const SizedBox(width: 16),
          Expanded(child: _buildChartContainer('Monthly Revenue', Icons.monetization_on_rounded, revenueData, _Palette.success, true)),
        ],
      );
    }
  }

  Widget _buildChartContainer(String title, IconData icon, List<double> data, Color color, bool isRevenue) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Ensuring dynamic internal spacing limits
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.2)),
            ],
          ),
          const SizedBox(height: 22),
          _buildBarChart(data: data, color: color, isRevenue: isRevenue),
        ],
      ),
    );
  }

  Widget _buildBarChart({required List<double> data, required Color color, bool isRevenue = false}) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    double maxValue = 0.0;
    for (var value in data) {
      if (value > maxValue) maxValue = value;
    }

    final double maxHeight = 70.0;

    return Container(
      // FIXED: Increased height to 165 from 140 to comfortably clear text sizes without bottom overflows
      height: 165,
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(12, (index) {
          final double value = data.length > index ? data[index] : 0.0;
          final double normalizedHeight = maxValue > 0 ? (value / maxValue) * maxHeight : 4.0;
          final String displayValue = isRevenue ? '₹${value.toInt()}' : value.toInt().toString();

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // FittedBox prevents large numeric text wraps from pushing layout height
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(displayValue, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: value > 0 ? color : Colors.transparent)),
              ),
              const SizedBox(height: 6),
              Container(
                height: normalizedHeight,
                width: 14,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [color.withOpacity(0.35), color],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: value > 0
                      ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 5, offset: const Offset(0, 2))]
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(months[index], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _Palette.muted)),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildRecentBookings() {
    if (_recentBookings.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: _Palette.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _Palette.bg, shape: BoxShape.circle),
                child: Icon(Icons.receipt_long_rounded, color: Colors.grey.shade400, size: 28),
              ),
              const SizedBox(height: 12),
              const Text('No recent bookings', style: TextStyle(color: _Palette.muted, fontSize: 14.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Bookings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.3)),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: _Palette.accent),
                child: const Text('View All', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentBookings.length > 5 ? 5 : _recentBookings.length,
            separatorBuilder: (context, index) => Divider(color: _Palette.hairline, height: 1),
            itemBuilder: (context, index) {
              final booking = _recentBookings[index];
              return _buildBookingItem(booking);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBookingItem(Map<String, dynamic> booking) {
    final bool isConfirmed = booking['status'] == 'confirmed';
    final statusColor = isConfirmed ? _Palette.success : _Palette.warning;
    final statusText = booking['status']?.toString().toUpperCase() ?? 'PENDING';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _Palette.bg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.local_parking_rounded, color: _Palette.inkSoft, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(booking['booking_number'] ?? 'BKG-0000', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _Palette.ink)),
                const SizedBox(height: 4),
                Text('Vehicle: ${booking['vehicle_number'] ?? 'N/A'}  •  ₹${booking['total_amount'] ?? '0'}', style: const TextStyle(fontSize: 12, color: _Palette.muted, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor, letterSpacing: 0.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}