import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'api_service.dart';

class OwnerBookingScreen extends StatefulWidget {
  const OwnerBookingScreen({Key? key}) : super(key: key);

  @override
  State<OwnerBookingScreen> createState() => _OwnerBookingScreenState();
}

class _OwnerBookingScreenState extends State<OwnerBookingScreen> {
  bool _isLoading = true;
  String? _ownerId;
  String _userEmail = '';

  List<dynamic> _ownerBookings = [];
  List<dynamic> _filteredBookings = [];
  List<dynamic> _customers = [];
  List<dynamic> _parkings = [];

  // Filter Variables
  String _filterStatus = 'All Status';
  String _searchQuery = '';
  DateTime? _filterDate;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Get Logged in Session
      final session = await ApiService.getUserSession();
      _userEmail = session['email']?.toString() ?? '';

      // 2. Fetch all required APIs concurrently
      final responses = await Future.wait([
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=parking_space_owners')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=parking_spaces')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=bookings')),
        http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=customers')),
      ]);

      if (mounted) {
        // Parse Responses
        final ownersData = json.decode(responses[0].body);
        final parkingsData = json.decode(responses[1].body);
        final bookingsData = json.decode(responses[2].body);
        final customersData = json.decode(responses[3].body);

        // Find Owner ID
        if (ownersData['status'] == true && ownersData['data'] != null) {
          for (var owner in ownersData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase() ||
                owner['user_id']?.toString() == session['userId']) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
          _ownerId ??= (ownersData['data'] as List).isNotEmpty ? ownersData['data'][0]['id'].toString() : '1';
        }

        // Filter Parkings for this Owner
        List<String> myParkingIds = [];
        if (parkingsData['status'] == true && parkingsData['data'] != null) {
          _parkings = parkingsData['data'];
          myParkingIds = _parkings
              .where((p) => p['owner_id'].toString() == _ownerId)
              .map((p) => p['id'].toString())
              .toList();
        }

        // Store Customers
        if (customersData['status'] == true && customersData['data'] != null) {
          _customers = customersData['data'];
        }

        // Filter Bookings for myParkingIds
        if (bookingsData['status'] == true && bookingsData['data'] != null) {
          final allBookings = bookingsData['data'] as List;
          _ownerBookings = allBookings.where((b) => myParkingIds.contains(b['parking_id'].toString())).toList();
        }

        _applyFilters();
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      _showSnackBar('Failed to load bookings.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredBookings = _ownerBookings.where((b) {
        // Status Match
        final bStatus = b['status']?.toString().toLowerCase() ?? '';
        final matchesStatus = _filterStatus == 'All Status' || bStatus == _filterStatus.toLowerCase();

        // Date Match
        bool matchesDate = true;
        if (_filterDate != null) {
          final bDateStr = b['booking_date']?.toString() ?? '';
          final formattedFilterDate = "${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}";
          matchesDate = bDateStr.startsWith(formattedFilterDate);
        }

        // Search Match
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
    // Format full time string for modal (e.g. 2026-07-31T06:11:00...)
    final startTime = booking['start_time'] ?? '';
    final endTime = booking['end_time'] ?? '';
    final fullTimeStr = "${booking['booking_date']}T$startTime.000000Z - ${booking['booking_date']}T$endTime.000000Z";

    final durationStr = "${booking['duration']} hour(s)";
    final amount = double.tryParse(booking['total_amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';

    final statusStr = booking['status']?.toString().toUpperCase() ?? 'PENDING';
    MaterialColor sColor = Colors.blue;
    if (statusStr == 'PENDING') sColor = Colors.orange;
    if (statusStr == 'CONFIRMED' || statusStr == 'COMPLETED') sColor = Colors.blue;
    if (statusStr == 'CANCELLED') sColor = Colors.red;

    final payStr = booking['payment_status']?.toString().toUpperCase() ?? 'PENDING';
    MaterialColor pColor = Colors.orange;
    if (payStr == 'PAID') pColor = Colors.green;
    if (payStr == 'FAILED') pColor = Colors.red;

    final bookedOn = booking['created_at'] ?? 'N/A';

    showDialog(
      context: context,
      builder: (ctx) {
        final isMobile = MediaQuery.of(ctx).size.width < 600;

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: isMobile ? double.infinity : 600,
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.assignment, color: Colors.orange, size: 24),
                          SizedBox(width: 12),
                          Text('Booking Details', style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildDetailRow('Booking #', Text('#$bNum', style: TextStyle(color: Colors.blue.shade700, fontSize: 14, fontWeight: FontWeight.bold))),
                  _buildDetailRow('Customer', Text(cName, style: const TextStyle(color: Colors.black, fontSize: 14))),
                  _buildDetailRow('Email', Text(cEmail, style: const TextStyle(color: Colors.black, fontSize: 14))),
                  _buildDetailRow('Phone', Text(cPhone, style: const TextStyle(color: Colors.black, fontSize: 14))),
                  _buildDetailRow('Parking Space', Text(pName, style: const TextStyle(color: Colors.black, fontSize: 14))),
                  _buildDetailRow('Vehicle', Text(vehicleStr, style: const TextStyle(color: Colors.black, fontSize: 14))),
                  _buildDetailRow('Date', Text(dateStr, style: const TextStyle(color: Colors.black, fontSize: 14))),
                  _buildDetailRow('Time', Text(fullTimeStr, style: TextStyle(color: Colors.blue.shade700, fontSize: 12))),
                  _buildDetailRow('Duration', Text(durationStr, style: const TextStyle(color: Colors.black, fontSize: 14))),
                  _buildDetailRow('Amount', Text('₹$amount', style: TextStyle(color: Colors.green.shade700, fontSize: 14, fontWeight: FontWeight.bold))),

                  _buildDetailRow('Status', Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: sColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: sColor.withOpacity(0.5))),
                    child: Text(statusStr.substring(0, 1).toUpperCase() + statusStr.substring(1).toLowerCase(), style: TextStyle(color: sColor.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                  )),

                  _buildDetailRow('Payment Status', Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: pColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: pColor.withOpacity(0.5))),
                    child: Text(payStr.substring(0, 1).toUpperCase() + payStr.substring(1).toLowerCase(), style: TextStyle(color: pColor.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                  )),

                  _buildDetailRow('Booked On', Text(bookedOn, style: const TextStyle(color: Colors.black, fontSize: 14)), showDivider: false),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, Widget valueWidget, {bool showDivider = true}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w600))),
              Expanded(child: valueWidget),
            ],
          ),
        ),
        if (showDivider) Divider(color: Colors.grey.shade300, height: 1),
      ],
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    // Stat Counters based on ALL owner bookings
    int totalCount = _ownerBookings.length;
    int pendingCount = _ownerBookings.where((b) => b['status']?.toString().toLowerCase() == 'pending').length;
    int confirmedCount = _ownerBookings.where((b) => b['status']?.toString().toLowerCase() == 'confirmed').length;
    int completedCount = _ownerBookings.where((b) => b['status']?.toString().toLowerCase() == 'completed').length;

    double totalRevenue = 0.0;
    for (var b in _ownerBookings) {
      totalRevenue += double.tryParse(b['total_amount']?.toString() ?? '0') ?? 0;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.calendar_month, color: Colors.blue, size: 28),
                    SizedBox(width: 12),
                    Text('My Bookings', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Manage bookings for your parking spaces', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

                // Stats Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatCard('Total', totalCount.toString(), Colors.blue, Icons.analytics),
                      const SizedBox(width: 12),
                      _buildStatCard('Pending', pendingCount.toString(), Colors.orange, Icons.hourglass_empty),
                      const SizedBox(width: 12),
                      _buildStatCard('Confirmed', confirmedCount.toString(), Colors.green, Icons.check_circle),
                      const SizedBox(width: 12),
                      _buildStatCard('Completed', completedCount.toString(), Colors.blue, Icons.circle),
                      const SizedBox(width: 12),
                      _buildStatCard('Revenue', '₹${totalRevenue.toStringAsFixed(0)}', Colors.green, Icons.monetization_on, isRevenue: true),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Filters Container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
                  child: Wrap(
                    spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      _buildFilterDropdown(),
                      _buildFilterDatePicker(),
                      _buildFilterSearch(),
                      ElevatedButton.icon(
                        onPressed: _applyFilters,
                        icon: const Icon(Icons.search, color: Colors.white, size: 16),
                        label: const Text('Filter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                      OutlinedButton(
                        onPressed: _resetFilters,
                        style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('Reset', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Data Table
                _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                    : _filteredBookings.isEmpty
                    ? Container(width: double.infinity, padding: const EdgeInsets.all(40), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)), child: Center(child: Text('No bookings found.', style: TextStyle(color: Colors.grey.shade600))))
                    : _buildBookingList(),

                const SizedBox(height: 30),
              ],
            ),
          ),
          if (_isLoading && _ownerBookings.isEmpty) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String count, Color color, IconData icon, {bool isRevenue = false}) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          Text(count, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isRevenue ? Colors.orange : color, size: 14),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status', style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterStatus,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black, fontSize: 13),
                items: ['All Status', 'Pending', 'Confirmed', 'Completed', 'Cancelled'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => _filterStatus = val!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDatePicker() {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Date', style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
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
                            primary: Colors.blue,
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
            style: const TextStyle(color: Colors.black, fontSize: 13),
            decoration: InputDecoration(
              hintText: _filterDate == null ? 'mm/dd/yyyy' : "${_filterDate!.month}/${_filterDate!.day}/${_filterDate!.year}",
              hintStyle: const TextStyle(color: Colors.black87),
              suffixIcon: Icon(Icons.calendar_today, color: Colors.grey.shade600, size: 16),
              filled: true, fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSearch() {
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search', style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => _searchQuery = val,
            style: const TextStyle(color: Colors.black, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by booking #, customer, vehicle...',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true, fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredBookings.length,
      itemBuilder: (context, index) {
        final booking = _filteredBookings[index];

        final statusStr = booking['status']?.toString().toUpperCase() ?? 'PENDING';
        MaterialColor sColor = Colors.orange;
        if (statusStr == 'CONFIRMED' || statusStr == 'COMPLETED') sColor = Colors.blue;
        if (statusStr == 'CANCELLED') sColor = Colors.red;

        final payStr = booking['payment_status']?.toString().toUpperCase() ?? 'PENDING';
        MaterialColor pColor = Colors.orange;
        if (payStr == 'PAID') pColor = Colors.green;
        if (payStr == 'FAILED') pColor = Colors.red;

        final customerName = _getCustomerName(booking['customer_id']?.toString());
        final parkingName = _getParkingName(booking['parking_id']?.toString());
        final vehicleType = booking['vehicle_type']?.toString().toUpperCase() ?? 'VEHICLE';
        final vehicleNum = booking['vehicle_number'] ?? 'N/A';
        final amount = double.tryParse(booking['total_amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';

        // Simple manual date mapping to match screenshot (e.g. 2026-07-27 to 27 Jul 2026)
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildListColumn('BOOKING #', '#${booking['booking_number']}', width: 140, isBold: true, valueColor: Colors.blue.shade700),
                _buildListColumn('CUSTOMER', customerName, width: 140, isBold: true),
                _buildListColumn('PARKING', parkingName, width: 140, valueColor: Colors.green.shade700),
                _buildListColumn('VEHICLE', '$vehicleType ($vehicleNum)', width: 160),
                _buildListColumn('DATE', displayDate, width: 100),
                _buildListColumn('AMOUNT', '₹$amount', width: 90, isBold: true, valueColor: Colors.green.shade700),

                SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STATUS', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: sColor.withOpacity(0.1), border: Border.all(color: sColor.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)),
                        child: Text(statusStr.substring(0, 1).toUpperCase() + statusStr.substring(1).toLowerCase(), style: TextStyle(color: sColor.shade700, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PAYMENT', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: pColor.withOpacity(0.1), border: Border.all(color: pColor.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)),
                        child: Text(payStr.substring(0, 1).toUpperCase() + payStr.substring(1).toLowerCase(), style: TextStyle(color: pColor.shade700, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                SizedBox(
                  width: 60,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIONS', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _showBookingDetails(booking),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
                          child: const Icon(Icons.remove_red_eye, color: Colors.blue, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListColumn(String title, String value, {bool isBold = false, Color valueColor = Colors.black, required double width}) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}