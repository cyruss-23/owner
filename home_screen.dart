// owner_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // ⭐ Add this import

import 'api_service.dart';
import 'login_screen.dart';
import 'owner_booking_screen.dart';
import 'owner_money_screen.dart';
import 'owner_more_screen.dart';
import 'owner_parking_screen.dart';

class _Palette {
  static const Color ink = Color(0xFF000000);
  static const Color inkSoft = Color(0xFF1C1C1E);
  static const Color accent = Color(0xFF2F6FED);
  static const Color accentDeep = Color(0xFF1849B8);
  static const Color success = Color(0xFF05944F);
  static const Color warning = Color(0xFFE8890C);
  static const Color danger = Color(0xFFD93025);
  static const Color bg = Color(0xFFF3F3F3);
  static const Color card = Colors.white;
  static const Color muted = Color(0xFF6B6B6B);
  static const Color hairline = Color(0xFFE6E6E6);
  static const Color chip = Color(0xFFF1F1F1);
}

class _Radius {
  static const double card = 16;
  static const double pill = 100;
  static const double field = 12;
}

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({Key? key}) : super(key: key);

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = {};

  List<dynamic> _ownerBookings = [];
  List<dynamic> _filteredBookings = [];
  List<dynamic> _customers = [];
  List<dynamic> _parkings = [];

  String _filterStatus = 'All Status';
  String _searchQuery = '';
  DateTime? _filterDate;
  final TextEditingController _searchCtrl = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  String _userName = 'User';
  String _userEmail = '';
  String _roleId = '3';
  String? _ownerId;

  bool _isStartingSession = false;

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
    _searchCtrl.dispose();
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
      final responses = await Future.wait([
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=bookings')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=parking_spaces')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=parking_space_owners')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=customers')),
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
        if (responses[3].statusCode == 200) {
          final cData = json.decode(responses[3].body);
          if (cData['status'] == true) _customers = cData['data'] ?? [];
        }

        List<dynamic> targetBookings = [];
        List<dynamic> targetParkings = [];

        for (var owner in allOwners) {
          if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase()) {
            _ownerId = owner['id'].toString();
            break;
          }
        }

        if (_ownerId != null) {
          targetParkings = allParkings.where((p) => p['owner_id'].toString() == _ownerId).toList();
          _parkings = targetParkings;

          List<String> ownedParkingIds = targetParkings.map((p) => p['id'].toString()).toList();
          targetBookings = allBookings.where((b) => ownedParkingIds.contains(b['parking_id'].toString())).toList();
          _ownerBookings = targetBookings;
        }

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
            'rating': '4.8',
          };
          _isLoading = false;
        });

        _applyFilters();
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading dashboard: ${e.toString()}'),
            backgroundColor: _Palette.ink,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    }
  }

  // ==========================================
  // ⭐ UPDATED: SCAN OPTIONS
  // ==========================================
  void _showScanOptions() {
    final TextEditingController bookingCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Start Parking Session', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _Palette.ink)),
            const SizedBox(height: 6),
            const Text('Scan the customer\'s QR code or enter their booking number manually.', textAlign: TextAlign.center, style: TextStyle(color: _Palette.muted, fontSize: 13)),
            const SizedBox(height: 24),

            // ⭐ Option 1: Scan QR Code
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openQrScanner();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _Palette.chip,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _Palette.hairline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: _Palette.ink, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _Palette.ink)),
                            Text('Use camera to scan the customer\'s pass', style: TextStyle(color: _Palette.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _Palette.muted),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider(color: _Palette.hairline, thickness: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('OR', style: TextStyle(color: _Palette.muted, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const Expanded(child: Divider(color: _Palette.hairline, thickness: 1)),
              ],
            ),
            const SizedBox(height: 16),

            // ⭐ Option 2: Enter Number Manually
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: bookingCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. BKG202310123456',
                      labelText: 'Enter Booking Number',
                      filled: true,
                      fillColor: _Palette.chip,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      final bNum = bookingCtrl.text.trim().toUpperCase();
                      if (bNum.isNotEmpty) {
                        Navigator.pop(ctx);
                        _startParkingSession(bNum);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _Palette.ink,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Start Timer Manually', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ⭐ Camera Scanner Method
  // ⭐ Camera Scanner Method
  void _openQrScanner() {
    bool isProcessing = false; // Prevent multiple scans
    MobileScannerController scannerController = MobileScannerController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Stack(
          children: [
            MobileScanner(
              controller: scannerController,
              onDetect: (capture) async {
                if (isProcessing) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final code = barcodes.first.rawValue;
                  if (code != null && code.isNotEmpty) {
                    isProcessing = true;

                    // ⭐ Pause camera and vibrate
                    await scannerController.stop();
                    HapticFeedback.mediumImpact();

                    // ⭐ Show Confirmation Dialog
                    if (ctx.mounted) {
                      _showScanConfirmationDialog(ctx, code.trim().toUpperCase(), scannerController, () {
                        isProcessing = false; // Reset if dialog closed without action
                      });
                    }
                  }
                }
              },
            ),
            // Close button
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                onPressed: () {
                  scannerController.dispose();
                  Navigator.pop(ctx);
                },
              ),
            ),
            // Scanner Overlay
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Text(
                'Align QR code within the frame',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Dispose controller when bottom sheet closes
      scannerController.dispose();
    });
  }

  // ⭐ NEW: Confirmation Dialog after scanning
  void _showScanConfirmationDialog(
      BuildContext parentCtx,
      String bookingNumber,
      MobileScannerController scannerController,
      VoidCallback onCancel,
      ) {
    // Find booking to show details in dialog
    final booking = _ownerBookings.firstWhere(
          (b) => b['booking_number']?.toString().toUpperCase() == bookingNumber,
      orElse: () => null,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.qr_code_scanner_rounded, color: _Palette.success, size: 28),
            SizedBox(width: 8),
            Text('QR Scanned', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: booking == null
            ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Booking not found for this QR code.', style: TextStyle(color: _Palette.danger, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Scanned Data: $bookingNumber', style: const TextStyle(fontSize: 12, color: _Palette.muted)),
          ],
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Customer Details', style: TextStyle(fontSize: 12, color: _Palette.muted, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_getCustomerName(booking['customer_id']?.toString()), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text('Vehicle', style: TextStyle(fontSize: 12, color: _Palette.muted, fontWeight: FontWeight.bold)),
            Text('${booking['vehicle_number']} (${booking['vehicle_type']?.toString().toUpperCase()})', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('Booking Number', style: TextStyle(fontSize: 12, color: _Palette.muted, fontWeight: FontWeight.bold)),
            Text(booking['booking_number'], style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _Palette.chip, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.timer_rounded, color: _Palette.ink, size: 20),
                  const SizedBox(width: 8),
                  Text('Duration: ${booking['duration']} Hours', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              // Resume camera
              if (parentCtx.mounted) scannerController.start();
              onCancel(); // Allow scanning again
            },
            child: const Text('Cancel', style: TextStyle(color: _Palette.muted, fontWeight: FontWeight.bold)),
          ),
          if (booking != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(parentCtx); // Close scanner bottom sheet
                _startParkingSession(bookingNumber); // Start timer
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Start Timer', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _Palette.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }
  Future<void> _startParkingSession(String bookingNumber) async {
    setState(() => _isStartingSession = true);
    try {
      final booking = _ownerBookings.firstWhere(
            (b) => b['booking_number']?.toString().toUpperCase() == bookingNumber,
        orElse: () => null,
      );

      if (booking == null) {
        throw Exception('No booking found with number $bookingNumber');
      }

      final bookingId = booking['id']?.toString();
      final durationHours = int.tryParse(booking['duration']?.toString() ?? '1') ?? 1;

      final now = DateTime.now();
      final endTime = now.add(Duration(hours: durationHours));

      final newStartTime = DateFormat('HH:mm:00').format(now);
      final newEndTime = DateFormat('HH:mm:00').format(endTime);
      final newDate = DateFormat('yyyy-MM-dd').format(now);

      final res = await http.put(
        Uri.parse('https://parkfro.com/API.php/API.php?table=bookings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': bookingId,
          'status': 'active',
          'start_time': newStartTime,
          'end_time': newEndTime,
          'booking_date': newDate,
        }),
      );

      final data = json.decode(res.body);
      if (data is Map && data['status'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session started successfully!'), backgroundColor: _Palette.success),
        );
        await _loadDashboardData();
      } else {
        throw Exception('Failed to update database');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: _Palette.danger),
      );
    } finally {
      if (mounted) setState(() => _isStartingSession = false);
    }
  }

  // ==========================================
  // FILTERING LOGIC
  // ==========================================
  void _applyFilters() {
    setState(() {
      _filteredBookings = _ownerBookings.where((b) {
        final bStatus = b['status']?.toString().toLowerCase() ?? '';
        final matchesStatus = _filterStatus == 'All Status' || bStatus == _filterStatus.toLowerCase();

        bool matchesDate = true;
        if (_filterDate != null) {
          final bDateStr = b['booking_date']?.toString() ?? '';
          final formattedFilterDate = "${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}";
          matchesDate = bDateStr.startsWith(formattedFilterDate);
        }

        final searchLower = _searchQuery.toLowerCase();
        final matchesSearch = _searchQuery.isEmpty ||
            (b['booking_number']?.toString().toLowerCase().contains(searchLower) ?? false) ||
            (_getCustomerName(b['customer_id']?.toString()).toLowerCase().contains(searchLower)) ||
            (b['vehicle_number']?.toString().toLowerCase().contains(searchLower) ?? false);

        return matchesStatus && matchesDate && matchesSearch;
      }).toList();
    });
  }

  void _resetFilters() {
    setState(() {
      _filterStatus = 'All Status';
      _filterDate = null;
      _searchQuery = '';
      _searchCtrl.clear();
      _applyFilters();
    });
  }

  Map<String, dynamic>? _getCustomer(String? customerId) {
    if (customerId == null) return null;
    try { return _customers.firstWhere((c) => c['id'].toString() == customerId); } catch (_) { return null; }
  }

  Map<String, dynamic>? _getParking(String? parkingId) {
    if (parkingId == null) return null;
    try { return _parkings.firstWhere((p) => p['id'].toString() == parkingId); } catch (_) { return null; }
  }

  String _getCustomerName(String? customerId) {
    final customer = _getCustomer(customerId);
    return customer != null ? customer['full_name'] ?? 'Unknown' : 'User ID: $customerId';
  }

  String _getParkingName(String? parkingId) {
    final parking = _getParking(parkingId);
    return parking != null ? parking['name'] ?? 'Unknown' : 'Parking ID: $parkingId';
  }

  Future<void> _handleLogout() async {
    await ApiService.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const OwnerLoginScreen()),
          (route) => false,
    );
  }

  // ==========================================
  // UI HELPERS
  // ==========================================
  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'CONFIRMED':
        return _Palette.accent;
      case 'ACTIVE':
        return _Palette.success;
      case 'COMPLETED':
        return _Palette.success;
      case 'CANCELLED':
        return _Palette.danger;
      default:
        return _Palette.warning;
    }
  }

  Color _payColor(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return _Palette.success;
      case 'FAILED':
        return _Palette.danger;
      default:
        return _Palette.warning;
    }
  }

  Widget _pill(String text, Color color, {double fontSize = 11.5}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(_Radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.6)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13.5, color: _Palette.muted, height: 1.3)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _Palette.bg,
        extendBodyBehindAppBar: false,
        appBar: _buildAppBar(),
        bottomNavigationBar: _buildOwnerBottomBar(),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _loadDashboardData,
              color: _Palette.ink,
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
                      _buildMyBookingsSection(),
                      const SizedBox(height: 28),
                      _buildStatsGrid(),
                      const SizedBox(height: 28),
                      _buildChartsSection(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
            if (_isLoading && _ownerBookings.isEmpty)
              const Positioned(
                top: 0, left: 0, right: 0,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: _Palette.ink,
                  minHeight: 3,
                ),
              ),
            if (_isStartingSession)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      shape: const Border(bottom: BorderSide(color: _Palette.hairline, width: 1)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: _Palette.ink, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.local_parking_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          const Text(
            'Park Hub',
            style: TextStyle(color: _Palette.ink, fontWeight: FontWeight.w800, fontSize: 21, letterSpacing: -0.6),
          ),
        ],
      ),
      actions: [
        _appBarIconButton(Icons.qr_code_scanner_rounded, _showScanOptions, showDot: true),
        _appBarIconButton(Icons.logout_rounded, _handleLogout),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _appBarIconButton(IconData icon, VoidCallback onTap, {bool showDot = false}) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 8),
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: _Palette.chip, shape: BoxShape.circle),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(icon, color: _Palette.ink, size: 20),
            onPressed: onTap,
            splashRadius: 22,
          ),
        ),
        if (showDot)
          Positioned(
            top: 7,
            right: 7,
            child: Container(
              width: 9,
              height: 9,
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _Palette.hairline, width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
    final color = isActive ? _Palette.ink : _Palette.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                decoration: BoxDecoration(
                  color: isActive ? _Palette.chip : Colors.transparent,
                  borderRadius: BorderRadius.circular(_Radius.pill),
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
    );
  }

  Widget _buildWelcomeSection() {
    final now = DateTime.now();
    final dateString = DateFormat('EEE, d MMM').format(now);
    final initial = _userName.trim().isNotEmpty ? _userName.trim()[0].toUpperCase() : 'O';
    final hour = now.hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(color: _Palette.ink, fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userName,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(_Radius.pill),
                ),
                child: Text(dateString, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total earnings', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '₹${((_dashboardData['totalRevenue'] ?? 0) as num).toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(_Radius.pill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 16, color: _Palette.ink),
                    const SizedBox(width: 4),
                    Text('${_dashboardData['rating'] ?? '0.0'}', style: const TextStyle(color: _Palette.ink, fontSize: 13, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyBookingsSection() {
    int totalCount = _ownerBookings.length;
    int pendingCount = _ownerBookings.where((b) => b['status']?.toString().toLowerCase() == 'pending').length;
    int confirmedCount = _ownerBookings.where((b) => b['status']?.toString().toLowerCase() == 'confirmed').length;
    int activeCount = _ownerBookings.where((b) => b['status']?.toString().toLowerCase() == 'active').length;
    int completedCount = _ownerBookings.where((b) => b['status']?.toString().toLowerCase() == 'completed').length;

    double totalRevenue = 0.0;
    for (var b in _ownerBookings) {
      totalRevenue += double.tryParse(b['total_amount']?.toString() ?? '0') ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('My bookings', subtitle: 'Manage bookings for your parking spaces'),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _buildBookingStatCard('Total', totalCount.toString(), _Palette.ink, Icons.analytics_rounded),
              const SizedBox(width: 10),
              _buildBookingStatCard('Pending', pendingCount.toString(), _Palette.warning, Icons.hourglass_bottom_rounded),
              const SizedBox(width: 10),
              _buildBookingStatCard('Active', activeCount.toString(), _Palette.success, Icons.timer_rounded),
              const SizedBox(width: 10),
              _buildBookingStatCard('Completed', completedCount.toString(), _Palette.success, Icons.verified_rounded),
              const SizedBox(width: 10),
              _buildBookingStatCard('Revenue', '₹${totalRevenue.toStringAsFixed(0)}', _Palette.success, Icons.currency_rupee_rounded, isRevenue: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _Palette.card,
            borderRadius: BorderRadius.circular(_Radius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildFilterDropdown()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFilterDatePicker()),
                ],
              ),
              const SizedBox(height: 14),
              _buildFilterSearch(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _applyFilters,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _Palette.ink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Radius.field)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.search_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Apply filters', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      onPressed: _resetFilters,
                      style: TextButton.styleFrom(
                        backgroundColor: _Palette.chip,
                        foregroundColor: _Palette.ink,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Radius.field)),
                      ),
                      child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Text(
              '${_filteredBookings.length} ${_filteredBookings.length == 1 ? 'booking' : 'bookings'}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _Palette.ink),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _filteredBookings.isEmpty
            ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
            decoration: BoxDecoration(
              color: _Palette.card,
              borderRadius: BorderRadius.circular(_Radius.card),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: _Palette.chip, shape: BoxShape.circle),
                  child: const Icon(Icons.event_busy_rounded, color: _Palette.muted, size: 26),
                ),
                const SizedBox(height: 14),
                const Text('No bookings found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _Palette.ink)),
                const SizedBox(height: 4),
                const Text('Try changing or resetting your filters.', style: TextStyle(fontSize: 13, color: _Palette.muted)),
              ],
            ))
            : _buildBookingList(),
      ],
    );
  }

  Widget _buildBookingStatCard(String title, String count, Color color, IconData icon, {bool isRevenue = false}) {
    return Container(
      width: 124,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(_Radius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withOpacity(0.10), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(count, style: const TextStyle(color: _Palette.ink, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          ),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(color: _Palette.muted, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint, Color? hintColor, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: hintColor ?? _Palette.muted.withOpacity(0.7), fontSize: 13.5),
      suffixIcon: suffix,
      prefixIconConstraints: const BoxConstraints(minWidth: 40),
      filled: true,
      fillColor: _Palette.chip,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(_Radius.field), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_Radius.field), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_Radius.field), borderSide: const BorderSide(color: _Palette.ink, width: 1.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      isDense: true,
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: _Palette.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w700)),
  );

  Widget _buildFilterDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Status'),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: _Palette.chip, borderRadius: BorderRadius.circular(_Radius.field)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterStatus,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _Palette.ink),
              borderRadius: BorderRadius.circular(14),
              dropdownColor: Colors.white,
              style: const TextStyle(color: _Palette.ink, fontSize: 13.5, fontWeight: FontWeight.w600),
              items: ['All Status', 'Pending', 'Confirmed', 'Active', 'Completed', 'Cancelled'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => setState(() => _filterStatus = val!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Date'),
        SizedBox(
          height: 48,
          child: TextField(
            readOnly: true,
            onTap: () async {
              final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  builder: (ctx, child) => Theme(
                      data: ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: _Palette.ink,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                            onSurface: Colors.black,
                          )
                      ),
                      child: child!
                  )
              );
              if (date != null) setState(() => _filterDate = date);
            },
            style: const TextStyle(color: _Palette.ink, fontSize: 13.5, fontWeight: FontWeight.w600),
            decoration: _fieldDecoration(
              hint: _filterDate == null ? 'mm/dd/yyyy' : "${_filterDate!.month}/${_filterDate!.day}/${_filterDate!.year}",
              hintColor: _filterDate == null ? null : _Palette.ink,
              suffix: const Icon(Icons.calendar_today_rounded, color: _Palette.muted, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Search'),
        TextField(
          controller: _searchCtrl,
          onChanged: (val) => _searchQuery = val,
          style: const TextStyle(color: _Palette.ink, fontSize: 13.5, fontWeight: FontWeight.w500),
          decoration: _fieldDecoration(hint: 'Booking #, customer or vehicle').copyWith(
            prefixIcon: const Icon(Icons.search_rounded, color: _Palette.muted, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildBookingList() {
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredBookings.length,
      itemBuilder: (context, index) {
        final booking = _filteredBookings[index];

        final statusStr = booking['status']?.toString().toUpperCase() ?? 'PENDING';
        final sColor = _statusColor(statusStr);

        final payStr = booking['payment_status']?.toString().toUpperCase() ?? 'PENDING';
        final pColor = _payColor(payStr);

        final customerName = _getCustomerName(booking['customer_id']?.toString());
        final parkingName = _getParkingName(booking['parking_id']?.toString());
        final vehicleType = booking['vehicle_type']?.toString().toUpperCase() ?? 'VEHICLE';
        final vehicleNum = booking['vehicle_number'] ?? 'N/A';
        final amount = double.tryParse(booking['total_amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';

        String displayDate = booking['booking_date'] ?? 'N/A';
        if (displayDate.length >= 10) {
          try {
            final parts = displayDate.split('-');
            final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            final mIndex = int.parse(parts[1]) - 1;
            displayDate = "${parts[2]} ${months[mIndex]} ${parts[0]}";
          } catch (_) {}
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _Palette.card,
            borderRadius: BorderRadius.circular(_Radius.card),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(_Radius.card),
              onTap: () => _showBookingDetails(booking),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: _Palette.chip, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.local_parking_rounded, color: _Palette.ink, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(parkingName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.2)),
                              const SizedBox(height: 2),
                              Text('#${booking['booking_number']}  •  $displayDate', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: _Palette.muted, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('₹$amount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.3)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: _Palette.hairline),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(child: _infoTile(Icons.person_outline_rounded, 'Customer', customerName)),
                        const SizedBox(width: 12),
                        Expanded(child: _infoTile(Icons.directions_car_outlined, 'Vehicle', '$vehicleType ($vehicleNum)')),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _pill(_cap(statusStr), sColor),
                              _pill(_cap(payStr), pColor),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: _Palette.chip, borderRadius: BorderRadius.circular(_Radius.pill)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text('Details', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _Palette.ink)),
                              SizedBox(width: 2),
                              Icon(Icons.chevron_right_rounded, size: 18, color: _Palette.ink),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _Palette.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: _Palette.muted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: _Palette.ink, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  void _showBookingDetails(Map<String, dynamic> booking) {
    final customer = _getCustomer(booking['customer_id']?.toString());
    final parking = _getParking(booking['parking_id']?.toString());

    final bNum = booking['booking_number'] ?? 'N/A';
    final cName = customer != null ? customer['full_name'] : 'N/A';
    final cEmail = customer != null ? customer['email'] : 'N/A';
    final cPhone = customer != null ? customer['phone'] : 'N/A';
    final pName = parking != null ? parking['name'] : 'N/A';

    final vType = booking['vehicle_type']?.toString().toUpperCase() ?? '';
    final vNum = booking['vehicle_number'] ?? '';
    final vehicleStr = "$vType ($vNum)";

    final dateStr = booking['booking_date'] ?? 'N/A';
    final startTime = booking['start_time'] ?? '';
    final endTime = booking['end_time'] ?? '';
    final fullTimeStr = "${booking['booking_date']}T$startTime.000000Z - ${booking['booking_date']}T$endTime.000000Z";

    final durationStr = "${booking['duration']} hour(s)";
    final amount = double.tryParse(booking['total_amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';

    final statusStr = booking['status']?.toString().toUpperCase() ?? 'PENDING';
    final sColor = _statusColor(statusStr);

    final payStr = booking['payment_status']?.toString().toUpperCase() ?? 'PENDING';
    final pColor = _payColor(payStr);

    final bookedOn = booking['created_at'] ?? 'N/A';

    Widget valueText(String t, {Color color = _Palette.ink, bool bold = false, double size = 14}) =>
        Text(t, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Booking details', style: TextStyle(color: _Palette.ink, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          const SizedBox(height: 2),
                          Text('#$bNum', style: const TextStyle(color: _Palette.muted, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(ctx),
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: _Palette.chip, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: _Palette.ink, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: _Palette.ink, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total amount', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5)),
                            const SizedBox(height: 4),
                            Text('₹$amount', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                          ],
                        ),
                      ),
                      Wrap(
                        direction: Axis.vertical,
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          _darkPill(_cap(statusStr), sColor),
                          _darkPill(_cap(payStr), pColor),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                _buildDetailRow('Customer', valueText(cName, bold: true)),
                _buildDetailRow('Email', valueText(cEmail)),
                _buildDetailRow('Phone', valueText(cPhone)),
                _buildDetailRow('Parking space', valueText(pName, bold: true)),
                _buildDetailRow('Vehicle', valueText(vehicleStr)),
                _buildDetailRow('Date', valueText(dateStr)),
                _buildDetailRow('Time', valueText(fullTimeStr, color: _Palette.muted, size: 12)),
                _buildDetailRow('Duration', valueText(durationStr)),
                _buildDetailRow('Booked on', valueText(bookedOn), showDivider: false),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _darkPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(_Radius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: _Palette.ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, Widget valueWidget, {bool showDivider = true}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(label, style: const TextStyle(color: _Palette.muted, fontSize: 13.5, fontWeight: FontWeight.w500))),
              Expanded(child: valueWidget),
            ],
          ),
        ),
        if (showDivider) const Divider(color: _Palette.hairline, height: 1),
      ],
    );
  }

  Widget _buildStatsGrid() {
    List<Map<String, dynamic>> stats = [
      {'title': 'Total parkings', 'value': _dashboardData['totalParkings'] ?? 0, 'subtitle': '${_dashboardData['approvedParkings'] ?? 0} active', 'icon': Icons.local_parking_rounded, 'color': _Palette.accent},
      {'title': 'Total bookings', 'value': _dashboardData['totalBookings'] ?? 0, 'subtitle': '${_dashboardData['confirmedBookings'] ?? 0} confirmed', 'icon': Icons.calendar_month_rounded, 'color': _Palette.accent},
      {'title': 'Average rating', 'value': _dashboardData['rating'] ?? '0.0', 'subtitle': 'Based on reviews', 'icon': Icons.star_rounded, 'color': Colors.amber.shade700},
      {'title': 'Total revenue', 'value': '₹${(_dashboardData['totalRevenue'] ?? 0).toStringAsFixed(0)}', 'subtitle': 'Lifetime earnings', 'icon': Icons.payments_rounded, 'color': _Palette.success},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Overview'),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
          ),
          itemCount: stats.length,
          itemBuilder: (context, index) {
            final stat = stats[index];
            final Color c = stat['color'] as Color;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _Palette.card,
                borderRadius: BorderRadius.circular(_Radius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: c.withOpacity(0.10), shape: BoxShape.circle),
                    child: Icon(stat['icon'] as IconData, color: c, size: 18),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(stat['value'].toString(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.8), maxLines: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(stat['title'].toString(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _Palette.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: _Palette.chip, borderRadius: BorderRadius.circular(_Radius.pill)),
                        child: Text(stat['subtitle'].toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _Palette.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildChartsSection() {
    List<dynamic> monthlyBookingsData = _dashboardData['monthlyBookings'] ?? [];
    List<dynamic> monthlyRevenueData = _dashboardData['monthlyRevenue'] ?? [];

    List<double> bookingsData = monthlyBookingsData.map((e) => (e as num).toDouble()).toList();
    List<double> revenueData = monthlyRevenueData.map((e) => (e as num).toDouble()).toList();

    final isMobile = MediaQuery.of(context).size.width < 600;

    final children = <Widget>[
      _sectionTitle('Performance'),
      const SizedBox(height: 14),
    ];

    if (isMobile) {
      children.add(Column(
        children: [
          _buildChartContainer('Monthly bookings', Icons.bar_chart_rounded, bookingsData, _Palette.ink, false),
          const SizedBox(height: 12),
          _buildChartContainer('Monthly revenue', Icons.payments_rounded, revenueData, _Palette.success, true),
        ],
      ));
    } else {
      children.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildChartContainer('Monthly bookings', Icons.bar_chart_rounded, bookingsData, _Palette.ink, false)),
          const SizedBox(width: 12),
          Expanded(child: _buildChartContainer('Monthly revenue', Icons.payments_rounded, revenueData, _Palette.success, true)),
        ],
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildChartContainer(String title, IconData icon, List<double> data, Color color, bool isRevenue) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(_Radius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.08), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _Palette.ink, letterSpacing: -0.2)),
            ],
          ),
          const SizedBox(height: 20),
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
              SizedBox(
                width: 22,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(displayValue, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: value > 0 ? _Palette.inkSoft : Colors.transparent)),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: normalizedHeight,
                width: 12,
                decoration: BoxDecoration(
                  color: value > 0 ? color : _Palette.hairline,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 8),
              Text(months[index].substring(0, 1), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _Palette.muted)),
            ],
          );
        }),
      ),
    );
  }
}
