import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'api_service.dart';

class OwnerCheckinScreen extends StatefulWidget {
  const OwnerCheckinScreen({Key? key}) : super(key: key);

  @override
  State<OwnerCheckinScreen> createState() => _OwnerCheckinScreenState();
}

class _OwnerCheckinScreenState extends State<OwnerCheckinScreen> {
  bool _isLoading = true;
  String? _ownerId;
  String _userEmail = '';

  List<dynamic> _arrivingBookings = [];
  List<dynamic> _activeBookings = [];
  List<dynamic> _customers = [];
  List<dynamic> _parkings = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final session = await ApiService.getUserSession();
      _userEmail = session['email']?.toString() ?? '';

      final responses = await Future.wait([
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_space_owners')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_spaces')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=bookings')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=customers')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=booking_checkins')),
      ]);

      if (mounted) {
        final ownersData = json.decode(responses[0].body);
        final parkingsData = json.decode(responses[1].body);
        final bookingsData = json.decode(responses[2].body);
        final customersData = json.decode(responses[3].body);
        final checkinsData = json.decode(responses[4].body);

        // Find owner
        if (ownersData['status'] == true && ownersData['data'] != null) {
          for (var owner in ownersData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase()) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
        }

        if (_ownerId != null) {
          // Get my parkings
          List<String> myParkingIds = [];
          if (parkingsData['status'] == true && parkingsData['data'] != null) {
            _parkings = parkingsData['data'];
            myParkingIds = _parkings.where((p) => p['owner_id'].toString() == _ownerId).map((p) => p['id'].toString()).toList();
          }

          // Get customers
          if (customersData['status'] == true && customersData['data'] != null) {
            _customers = customersData['data'];
          }

          // Get bookings
          if (bookingsData['status'] == true && bookingsData['data'] != null) {
            final allBookings = bookingsData['data'] as List;
            final myBookings = allBookings.where((b) => myParkingIds.contains(b['parking_id'].toString())).toList();

            // Get check-in records
            Map<String, dynamic> checkinMap = {};
            if (checkinsData['status'] == true && checkinsData['data'] != null) {
              for (var c in checkinsData['data']) {
                checkinMap[c['booking_id'].toString()] = c;
              }
            }

            setState(() {
              // Arriving = confirmed bookings without check-in
              _arrivingBookings = myBookings.where((b) {
                final status = b['status']?.toString().toLowerCase() ?? '';
                return (status == 'confirmed' || status == 'pending') &&
                    !checkinMap.containsKey(b['id'].toString());
              }).toList();

              // Active = checked-in but not checked-out
              _activeBookings = myBookings.where((b) {
                final checkin = checkinMap[b['id'].toString()];
                return checkin != null && checkin['checkout_time'] == null && checkin['no_show'] != 1;
              }).toList();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      _showSnackBar('Failed to load check-in data.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkIn(Map<String, dynamic> booking) async {
    try {
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final response = await http.post(
        Uri.parse('https://parkfro.com/API.php?table=booking_checkins'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'booking_id': booking['id'].toString(),
          'checkin_time': now,
          'checkin_by': _ownerId ?? '1',
          'no_show': '0',
          'overstay_minutes': '0',
          'extra_amount': '0.00',
        },
      );

      if (response.statusCode == 200) {
        // Also update booking status
        await http.put(
          Uri.parse('https://parkfro.com/API.php?table=bookings'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'id': booking['id'].toString(), 'status': 'active'}),
        );

        _showSnackBar('Customer checked in successfully!', Colors.green);
        _fetchData();
      } else {
        _showSnackBar('Failed to check in.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
    }
  }

  Future<void> _checkOut(Map<String, dynamic> booking) async {
    try {
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

      // Get checkin record id
      final checkinRes = await http.get(Uri.parse('https://parkfro.com/API.php?table=booking_checkins'));
      String? checkinId;
      if (checkinRes.statusCode == 200) {
        final data = json.decode(checkinRes.body);
        if (data['status'] == true && data['data'] != null) {
          for (var c in data['data']) {
            if (c['booking_id'].toString() == booking['id'].toString()) {
              checkinId = c['id'].toString();
              break;
            }
          }
        }
      }

      if (checkinId == null) {
        _showSnackBar('Check-in record not found.', Colors.red);
        return;
      }

      final response = await http.put(
        Uri.parse('https://parkfro.com/API.php?table=booking_checkins'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': checkinId,
          'checkout_time': now,
          'checkout_by': _ownerId ?? '1',
        }),
      );

      if (response.statusCode == 200) {
        await http.put(
          Uri.parse('https://parkfro.com/API.php?table=bookings'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'id': booking['id'].toString(), 'status': 'completed'}),
        );

        _showSnackBar('Customer checked out successfully!', Colors.green);
        _fetchData();
      } else {
        _showSnackBar('Failed to check out.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
    }
  }

  Future<void> _markNoShow(Map<String, dynamic> booking) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Mark as No-Show', style: TextStyle(color: Colors.black)),
        content: const Text('Are you sure this customer did not arrive?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, No-Show', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final response = await http.post(
        Uri.parse('https://parkfro.com/API.php?table=booking_checkins'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'booking_id': booking['id'].toString(),
          'no_show': '1',
          'no_show_marked_at': now,
          'checkin_by': _ownerId ?? '1',
          'overstay_minutes': '0',
          'extra_amount': '0.00',
        },
      );

      if (response.statusCode == 200) {
        await http.put(
          Uri.parse('https://parkfro.com/API.php?table=bookings'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'id': booking['id'].toString(), 'status': 'no_show'}),
        );

        _showSnackBar('Marked as No-Show', Colors.orange);
        _fetchData();
      } else {
        _showSnackBar('Failed to mark no-show.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
    }
  }

  String _getCustomerName(String? customerId) {
    if (customerId == null) return 'Unknown';
    try {
      final c = _customers.firstWhere((c) => c['id'].toString() == customerId);
      return c['full_name'] ?? 'Unknown';
    } catch (_) {
      return 'Customer #$customerId';
    }
  }

  String _getParkingName(String? parkingId) {
    if (parkingId == null) return 'Unknown';
    try {
      final p = _parkings.firstWhere((p) => p['id'].toString() == parkingId);
      return p['name'] ?? 'Unknown';
    } catch (_) {
      return 'Parking #$parkingId';
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.login, color: Colors.blue, size: 28),
                    SizedBox(width: 12),
                    Text('Check-in / Check-out', style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Manage arriving and active customers', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

                // Arriving Section
                _buildSectionHeader('Arriving Customers', Icons.person_pin_circle, Colors.orange, _arrivingBookings.length),
                const SizedBox(height: 12),
                _arrivingBookings.isEmpty
                    ? _buildEmptyState('No arriving customers')
                    : Column(children: _arrivingBookings.map((b) => _buildArrivingCard(b)).toList()),

                const SizedBox(height: 32),

                // Active Section
                _buildSectionHeader('Active (Checked-in)', Icons.directions_car, Colors.green, _activeBookings.length),
                const SizedBox(height: 12),
                _activeBookings.isEmpty
                    ? _buildEmptyState('No active customers')
                    : Column(children: _activeBookings.map((b) => _buildActiveCard(b)).toList()),

                const SizedBox(height: 30),
              ],
            ),
          ),
          if (_isLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Center(child: Text(msg, style: TextStyle(color: Colors.grey.shade600))),
    );
  }

  Widget _buildArrivingCard(Map<String, dynamic> booking) {
    final customerName = _getCustomerName(booking['customer_id']?.toString());
    final parkingName = _getParkingName(booking['parking_id']?.toString());
    final vehicleType = booking['vehicle_type']?.toString().toUpperCase() ?? 'VEHICLE';
    final vehicleNum = booking['vehicle_number'] ?? 'N/A';
    final startTime = booking['start_time'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('#${booking['booking_number']}', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text('ARRIVING', style: TextStyle(color: Colors.orange.shade700, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Customer', customerName),
          _buildInfoRow('Vehicle', '$vehicleType ($vehicleNum)'),
          _buildInfoRow('Parking', parkingName),
          _buildInfoRow('Expected', startTime),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _checkIn(booking),
                  icon: const Icon(Icons.login, color: Colors.white, size: 16),
                  label: const Text('CHECK IN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _markNoShow(booking),
                  icon: const Icon(Icons.person_off, color: Colors.red, size: 16),
                  label: const Text('NO SHOW', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCard(Map<String, dynamic> booking) {
    final customerName = _getCustomerName(booking['customer_id']?.toString());
    final parkingName = _getParkingName(booking['parking_id']?.toString());
    final vehicleType = booking['vehicle_type']?.toString().toUpperCase() ?? 'VEHICLE';
    final vehicleNum = booking['vehicle_number'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('#${booking['booking_number']}', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text('ACTIVE', style: TextStyle(color: Colors.green.shade700, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Customer', customerName),
          _buildInfoRow('Vehicle', '$vehicleType ($vehicleNum)'),
          _buildInfoRow('Parking', parkingName),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _checkOut(booking),
              icon: const Icon(Icons.logout, color: Colors.white, size: 16),
              label: const Text('CHECK OUT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}