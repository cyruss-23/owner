import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'api_service.dart';
import 'kyc_screen.dart';
import 'more/owner_attendance_screen.dart';
import 'more/owner_capacity_block_screen.dart';
import 'more/owner_closure_screen.dart';
import 'more/owner_ev_screen.dart';
import 'more/owner_extension_screen.dart';
import 'more/owner_incident_screen.dart';
import 'more/owner_notifications_screen.dart';
import 'more/owner_pricing_screen.dart';
import 'more/owner_reviews_screen.dart';
import 'more/owner_settlement_screen.dart';
import 'more/owner_shift_screen.dart';
import 'more/owner_staff_screen.dart';
import 'more/owner_staff_screen.dart';
import 'owner_analytics_screen.dart';
import 'owner_overstay_screen.dart';
import 'owner_qr_screen.dart';
import 'owner_support_screen.dart';
import 'login_screen.dart';
import 'owner_walkin_screen.dart';

class OwnerMoreScreen extends StatefulWidget {
  const OwnerMoreScreen({Key? key}) : super(key: key);

  @override
  State<OwnerMoreScreen> createState() => _OwnerMoreScreenState();
}

class _OwnerMoreScreenState extends State<OwnerMoreScreen> {
  bool _isLoading = true;
  Map<String, String?> _session = {};
  String _kycStatus = 'NOT SUBMITTED';
  String? _ownerId;

  int _totalParkings = 0;
  List<dynamic> _ownerBookings = [];
  List<dynamic> _parkings = [];
  List<dynamic> _customers = [];

  // Filter state
  String _filterStatus = 'All';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _session = await ApiService.getUserSession();
      final email = _session['email']?.toString() ?? '';

      // Fetch everything concurrently
      final responses = await Future.wait([
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_space_owners')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_spaces')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=bookings')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=customers')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=owner_kyc')),
      ]);

      final ownersData = json.decode(responses[0].body);
      final parkingsData = json.decode(responses[1].body);
      final bookingsData = json.decode(responses[2].body);
      final customersData = json.decode(responses[3].body);
      final kycData = json.decode(responses[4].body);

      // 1. Find owner id from email
      _ownerId = null;
      if (ownersData['status'] == true && ownersData['data'] != null) {
        for (var owner in ownersData['data']) {
          if (owner['email']?.toString().toLowerCase() == email.toLowerCase()) {
            _ownerId = owner['id'].toString();
            break;
          }
        }
      }

      // 2. Get parkings owned by this owner
      _parkings = [];
      List<String> myParkingIds = [];
      if (parkingsData['status'] == true && parkingsData['data'] != null && _ownerId != null) {
        _parkings = (parkingsData['data'] as List)
            .where((p) => p['owner_id'].toString() == _ownerId)
            .toList();
        myParkingIds = _parkings.map((p) => p['id'].toString()).toList();
        _totalParkings = _parkings.length;
      }

      // 3. Get customers (for names)
      _customers = [];
      if (customersData['status'] == true && customersData['data'] != null) {
        _customers = customersData['data'];
      }

      // 4. Filter bookings for my parkings ONLY
      _ownerBookings = [];
      if (bookingsData['status'] == true && bookingsData['data'] != null && myParkingIds.isNotEmpty) {
        _ownerBookings = (bookingsData['data'] as List)
            .where((b) => myParkingIds.contains(b['parking_id'].toString()))
            .toList();
        // Sort latest first
        _ownerBookings.sort((a, b) =>
            (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
      }

      // 5. KYC status
      _kycStatus = 'NOT SUBMITTED';
      if (kycData['status'] == true && kycData['data'] != null && _ownerId != null) {
        for (var k in kycData['data']) {
          if (k['owner_id'].toString() == _ownerId) {
            _kycStatus = k['status']?.toString().toUpperCase() ?? 'PENDING';
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filteredBookings {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _ownerBookings.where((b) {
      // Status filter
      if (_filterStatus != 'All') {
        final bStatus = b['status']?.toString().toLowerCase() ?? '';
        if (bStatus != _filterStatus.toLowerCase()) return false;
      }
      // Search filter
      if (query.isNotEmpty) {
        final bookingNum = b['booking_number']?.toString().toLowerCase() ?? '';
        final vehicle = b['vehicle_number']?.toString().toLowerCase() ?? '';
        final custName = _getCustomerName(b['customer_id']?.toString()).toLowerCase();
        if (!bookingNum.contains(query) && !vehicle.contains(query) && !custName.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _getCustomerName(String? customerId) {
    if (customerId == null) return 'Customer #$customerId';
    try {
      final c = _customers.firstWhere((c) => c['id'].toString() == customerId);
      return c['full_name']?.toString() ?? 'Customer #$customerId';
    } catch (_) {
      return 'Customer #$customerId';
    }
  }

  String _getParkingName(String? parkingId) {
    if (parkingId == null) return 'N/A';
    try {
      final p = _parkings.firstWhere((p) => p['id'].toString() == parkingId);
      return p['name']?.toString() ?? 'Parking #$parkingId';
    } catch (_) {
      return 'Parking #$parkingId';
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Logout', style: TextStyle(color: Colors.black)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const OwnerLoginScreen()),
              (route) => false,
        );
      }
    }
  }

  void _showBookingDetails(Map<String, dynamic> booking) {
    final customerName = _getCustomerName(booking['customer_id']?.toString());
    final parkingName = _getParkingName(booking['parking_id']?.toString());

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 50, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('Booking #${booking['booking_number'] ?? ''}', style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 20),
              _buildDetailItem('Customer', customerName),
              _buildDetailItem('Parking Space', parkingName),
              _buildDetailItem('Vehicle', '${booking['vehicle_type']?.toString().toUpperCase() ?? ''} (${booking['vehicle_number'] ?? ''})'),
              _buildDetailItem('Booking Date', booking['booking_date']?.toString() ?? ''),
              _buildDetailItem('Time', '${booking['start_time'] ?? ''} - ${booking['end_time'] ?? ''}'),
              _buildDetailItem('Duration', '${booking['duration'] ?? '0'} hour(s)'),
              _buildDetailItem('Amount', '₹${booking['total_amount'] ?? '0'}'),
              _buildDetailItem('Status', (booking['status']?.toString() ?? '').toUpperCase()),
              _buildDetailItem('Payment', (booking['payment_status']?.toString() ?? '').toUpperCase()),
              _buildDetailItem('Booked On', booking['created_at']?.toString() ?? ''),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _showComingSoon(String feature, String docRef) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.construction, color: Colors.orange, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(feature, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text('This feature is planned as part of your roadmap.\n\nReference: $docRef', style: TextStyle(color: Colors.grey.shade700, height: 1.5)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final userName = _session['fullName'] ?? 'Owner';
    final userEmail = _session['email'] ?? '';
    final roleId = _session['roleId'] ?? '3';

    Color kycColor = Colors.grey;
    if (_kycStatus == 'APPROVED') kycColor = Colors.green;
    if (_kycStatus == 'PENDING') kycColor = Colors.orange;
    if (_kycStatus == 'REJECTED') kycColor = Colors.red;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadData,
            color: Colors.blue,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ================= HEADER =================
                  const Row(
                    children: [
                      Icon(Icons.menu, color: Colors.blue, size: 28),
                      SizedBox(width: 12),
                      Text('More', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Profile, bookings, staff, reports and settings', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 24),

                  // ================= PROFILE CARD =================
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.black, Colors.grey.shade900]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                              child: const Icon(Icons.person, color: Colors.black, size: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(userName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(userEmail, style: TextStyle(color: Colors.grey.shade400, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                                    child: const Text('PARKING OWNER', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Divider(color: Colors.grey.shade800, height: 1),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildProfileStat('Parkings', _totalParkings.toString()),
                            Container(width: 1, height: 30, color: Colors.grey.shade800),
                            _buildProfileStat('Bookings', _ownerBookings.length.toString()),
                            Container(width: 1, height: 30, color: Colors.grey.shade800),
                            _buildProfileStat('KYC', _kycStatus),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ================= MY BOOKINGS =================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, color: Colors.blue, size: 22),
                          const SizedBox(width: 10),
                          const Text('My Bookings', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                            child: Text(_ownerBookings.length.toString(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Filter Row
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _filterStatus,
                              isExpanded: true,
                              dropdownColor: Colors.white,
                              style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
                              items: ['All', 'Confirmed', 'Pending', 'Completed', 'Cancelled', 'No_Show']
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) => setState(() => _filterStatus = val!),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: Colors.black, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search bookings...',
                            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 18),
                            filled: true, fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _isLoading
                      ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                      : _ownerBookings.isEmpty
                      ? _buildEmptyState('No bookings found for your parking spaces.')
                      : _filteredBookings.isEmpty
                      ? _buildEmptyState('No bookings match your filter.')
                      : Column(children: _filteredBookings.map((b) => _buildBookingCard(b)).toList()),

                  const SizedBox(height: 24),

                  // ================= BUSINESS =================
                  _buildSectionTitle('BUSINESS'),
                  _buildMenuTile(
                    icon: Icons.verified_user, color: Colors.blue,
                    title: 'KYC & Documents',
                    subtitle: 'Status: $_kycStatus',
                    trailingColor: kycColor,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const KycScreen()),
                    ).then((_) => _loadData()),
                  ),
                  _buildMenuTile(
                    icon: Icons.people_alt, color: Colors.purple,
                    title: 'Staff Management',
                    subtitle: 'Add managers & attendants',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerStaffScreen()),
                    ).then((_) => _loadData()),
                  ),
                  _buildMenuTile(
                    icon: Icons.schedule, color: Colors.teal,
                    title: 'Shift Management',
                    subtitle: 'Morning / Evening / Night',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerShiftScreen()),
                    ).then((_) => _loadData()),
                  ),
                  _buildMenuTile(
                    icon: Icons.event_busy, color: Colors.orange,
                    title: 'Scheduled Closures',
                    subtitle: 'Block parking for events',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerClosureScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.block, color: Colors.red,
                    title: 'Capacity Blocking',
                    subtitle: 'Reserve spaces',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerCapacityBlockScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.ev_station, color: Colors.purple,
                    title: 'EV Charging',
                    subtitle: 'Manage EV chargers',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerEvScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.qr_code, color: Colors.blue,
                    title: 'Parking QR Codes',
                    subtitle: 'Generate & print QR for entry',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerQrScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.local_offer, color: Colors.green,
                    title: 'Pricing Rules',
                    subtitle: 'View rates set by admin',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerPricingScreen()),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= OPERATIONS =================
                  _buildSectionTitle('OPERATIONS'),
                  _buildMenuTile(
                    icon: Icons.warning_amber, color: Colors.red,
                    title: 'Overstay Management',
                    subtitle: 'Vehicles exceeding booked time',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerOverstayScreen()),
                    ).then((_) => _loadData()),
                  ),
                  _buildMenuTile(
                    icon: Icons.more_time, color: Colors.purple,
                    title: 'Extension Requests',
                    subtitle: 'Approve / reject extensions',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerExtensionScreen()),
                    ).then((_) => _loadData()),
                  ),
                  _buildMenuTile(
                    icon: Icons.directions_car, color: Colors.blue,
                    title: 'Walk-In Entry',
                    subtitle: 'Register vehicles not booked through app',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerWalkinScreen()),
                    ).then((_) => _loadData()),
                  ),

                  _buildMenuTile(
                    icon: Icons.people, color: Colors.teal,
                    title: 'Staff Attendance',
                    subtitle: 'Check-in / check-out',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerAttendanceScreen()),
                    ).then((_) => _loadData()),
                  ),

                  const SizedBox(height: 20),

                  // ================= REPORTS & INSIGHTS =================
                  _buildSectionTitle('REPORTS & INSIGHTS'),
                  _buildMenuTile(
                    icon: Icons.analytics, color: Colors.green,
                    title: 'Analytics',
                    subtitle: 'Occupancy, revenue, heat map',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerAnalyticsScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.star, color: Colors.amber,
                    title: 'Reviews & Ratings',
                    subtitle: 'Customer feedback',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerReviewsScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.receipt_long, color: Colors.indigo,
                    title: 'Settlements',
                    subtitle: 'Revenue & payouts',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerSettlementScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.report_problem, color: Colors.red,
                    title: 'Incident Reports',
                    subtitle: 'Damage / accident / dispute',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerIncidentScreen()),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= SUPPORT & SETTINGS =================
                  _buildSectionTitle('SUPPORT & SETTINGS'),
                  _buildMenuTile(
                    icon: Icons.chat_bubble, color: Colors.blue,
                    title: 'Support & Complaints',
                    subtitle: 'Tickets & live chat',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerSupportScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.notifications, color: Colors.orange,
                    title: 'Notifications',
                    subtitle: 'Bookings, arrivals, alerts',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerNotificationsScreen()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.security, color: Colors.grey.shade700,
                    title: 'Security & Activity',
                    subtitle: 'Login history, device logs',
                    onTap: () => _showComingSoon('Security', 'Point 34 of your flow doc'),
                  ),

                  const SizedBox(height: 24),

                  // ================= LOGOUT =================
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout, color: Colors.red, size: 18),
                      label: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Center(
                    child: Text(
                      'Park Hub Owner v1.0.0\nRole ID: $roleId\nOwner ID: ${_ownerId ?? "N/A"}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3),
            ),
        ],
      ),
    );
  }
  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final statusStr = booking['status']?.toString().toLowerCase() ?? 'pending';
    Color sColor = Colors.orange;
    if (statusStr == 'confirmed') sColor = Colors.green;
    if (statusStr == 'completed') sColor = Colors.blue;
    if (statusStr == 'cancelled') sColor = Colors.red;
    if (statusStr == 'no_show') sColor = Colors.grey;

    final customerName = _getCustomerName(booking['customer_id']?.toString());
    final parkingName = _getParkingName(booking['parking_id']?.toString());
    final vehicleType = booking['vehicle_type']?.toString().toUpperCase() ?? 'VEHICLE';
    final vehicleNum = booking['vehicle_number'] ?? 'N/A';

    return InkWell(
      onTap: () => _showBookingDetails(booking),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('#${booking['booking_number'] ?? 'N/A'}',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: sColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: sColor.withOpacity(0.4))),
                  child: Text(statusStr.toUpperCase(), style: TextStyle(color: sColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.person, color: Colors.grey.shade500, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(customerName, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.local_parking, color: Colors.grey.shade500, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(parkingName, style: TextStyle(color: Colors.grey.shade700, fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.directions_car, color: Colors.grey.shade500, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text('$vehicleType • $vehicleNum', style: TextStyle(color: Colors.grey.shade700, fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${booking['booking_date'] ?? ''} • ${booking['duration'] ?? '0'}h',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                Text('₹${booking['total_amount'] ?? '0'}',
                    style: TextStyle(color: Colors.green.shade700, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Icon(Icons.inbox, color: Colors.grey.shade400, size: 40),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildProfileStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Color? trailingColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailingColor != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: trailingColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_kycStatus, style: TextStyle(color: trailingColor, fontSize: 9, fontWeight: FontWeight.bold)),
              )
            else
              Icon(Icons.arrow_forward_ios, color: Colors.grey.shade400, size: 14),
          ],
        ),
      ),
    );
  }
}