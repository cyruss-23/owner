import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'api_service.dart';

class OwnerOverstayScreen extends StatefulWidget {
  const OwnerOverstayScreen({Key? key}) : super(key: key);

  @override
  State<OwnerOverstayScreen> createState() => _OwnerOverstayScreenState();
}

class _OwnerOverstayScreenState extends State<OwnerOverstayScreen> {
  bool _isLoading = true;
  String? _ownerId;
  List<dynamic> _activeOverstays = [];
  List<dynamic> _resolved = [];
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
      final email = session['email']?.toString() ?? '';

      final responses = await Future.wait([
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_space_owners')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_spaces')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=overstay_records')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=bookings')),
      ]);

      final ownersData = json.decode(responses[0].body);
      final parkingsData = json.decode(responses[1].body);
      final overstayData = json.decode(responses[2].body);
      final bookingsData = json.decode(responses[3].body);

      if (ownersData['status'] == true && ownersData['data'] != null) {
        for (var o in ownersData['data']) {
          if (o['email']?.toString().toLowerCase() == email.toLowerCase()) {
            _ownerId = o['id'].toString();
            break;
          }
        }
      }

      List<String> myParkingIds = [];
      if (_ownerId != null && parkingsData['status'] == true && parkingsData['data'] != null) {
        _parkings = (parkingsData['data'] as List).where((p) => p['owner_id'].toString() == _ownerId).toList();
        myParkingIds = _parkings.map((p) => p['id'].toString()).toList();
      }

      List<dynamic> allOverstay = [];
      if (overstayData['status'] == true && overstayData['data'] != null) {
        allOverstay = (overstayData['data'] as List).where((o) => myParkingIds.contains(o['parking_id'].toString())).toList();
      }

      // Also scan bookings for natural overstay (end_time passed but not exited)
      final now = DateTime.now();
      final bookings = (bookingsData['status'] == true && bookingsData['data'] != null)
          ? (bookingsData['data'] as List).where((b) => myParkingIds.contains(b['parking_id'].toString())).toList()
          : [];
      for (var b in bookings) {
        if (b['status']?.toString().toLowerCase() != 'active') continue;
        try {
          final endDt = DateTime.parse('${b['booking_date']} ${b['end_time']}');
          if (now.isAfter(endDt)) {
            final mins = now.difference(endDt).inMinutes;
            if (!allOverstay.any((o) => o['booking_id']?.toString() == b['id'].toString())) {
              allOverstay.add({
                'id': 'auto_${b['id']}',
                'booking_id': b['id'],
                'parking_id': b['parking_id'],
                'vehicle_number': b['vehicle_number'],
                'booked_end_time': '${b['booking_date']} ${b['end_time']}',
                'overstay_minutes': mins,
                'extra_amount': (mins / 60 * 40).toStringAsFixed(2),
                'status': 'active',
                'is_auto': true,
              });
            }
          }
        } catch (_) {}
      }

      setState(() {
        _activeOverstays = allOverstay.where((o) => o['status']?.toString().toLowerCase() == 'active').toList();
        _resolved = allOverstay.where((o) => o['status']?.toString().toLowerCase() != 'active').toList();
      });
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveOverstay(Map<String, dynamic> o, String action) async {
    try {
      if (o['is_auto'] == true && action == 'collect') {
        // Create new overstay record
        await http.post(
          Uri.parse('https://parkfro.com/API.php?table=overstay_records'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'booking_id': o['booking_id']?.toString() ?? '',
            'parking_id': o['parking_id'].toString(),
            'vehicle_number': o['vehicle_number']?.toString() ?? '',
            'booked_end_time': o['booked_end_time'].toString(),
            'overstay_minutes': o['overstay_minutes'].toString(),
            'extra_amount': o['extra_amount'].toString(),
            'extra_paid': '1',
            'status': 'resolved',
          },
        );
      } else if (o['id'].toString().startsWith('auto_')) {
        await http.post(
          Uri.parse('https://parkfro.com/API.php?table=overstay_records'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'booking_id': o['booking_id']?.toString() ?? '',
            'parking_id': o['parking_id'].toString(),
            'vehicle_number': o['vehicle_number']?.toString() ?? '',
            'booked_end_time': o['booked_end_time'].toString(),
            'overstay_minutes': o['overstay_minutes'].toString(),
            'extra_amount': o['extra_amount'].toString(),
            'status': 'resolved',
          },
        );
      } else {
        await http.put(
          Uri.parse('https://parkfro.com/API.php?table=overstay_records'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'id': o['id'].toString(),
            'actual_exit_time': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
            'extra_paid': action == 'collect' ? '1' : '0',
            'status': 'resolved',
          }),
        );
      }
      _showSnackBar('Overstay resolved', Colors.green);
      _fetchData();
    } catch (e) {
      _showSnackBar('Failed: $e', Colors.red);
    }
  }

  void _showOptions(Map<String, dynamic> o) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Overstay: ${o['vehicle_number']}', style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Exceeded by ${o['overstay_minutes']} minutes • Extra ₹${o['extra_amount']}', style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            const SizedBox(height: 20),
            _buildOption(ctx, Icons.payments, 'Collect Extra Payment', Colors.green, () => _resolveOverstay(o, 'collect')),
            _buildOption(ctx, Icons.exit_to_app, 'Mark Exit (No Extra)', Colors.blue, () => _resolveOverstay(o, 'exit')),
            _buildOption(ctx, Icons.phone, 'Contact Customer', Colors.orange, () {
              Navigator.pop(ctx);
              _showSnackBar('Calling customer...', Colors.orange);
            }),
            _buildOption(ctx, Icons.access_time, 'Extend Booking', Colors.purple, () {
              Navigator.pop(ctx);
              _showSnackBar('Send extension request', Colors.purple);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext ctx, IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.3))),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _fetchData,
            color: Colors.blue,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.red, size: 28),
                      const SizedBox(width: 12),
                      const Text('Overstay Management', style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      if (_activeOverstays.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                          child: Text('${_activeOverstays.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Vehicles that exceeded their booked time', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 24),

                  _isLoading
                      ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                      : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE OVERSTAYS (${_activeOverstays.length})', style: TextStyle(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      _activeOverstays.isEmpty
                          ? _buildEmpty('No active overstays', Icons.check_circle, Colors.green)
                          : Column(children: _activeOverstays.map((o) => _buildOverstayCard(o)).toList()),
                      const SizedBox(height: 30),
                      Text('RESOLVED (${_resolved.length})', style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      _resolved.isEmpty
                          ? _buildEmpty('No resolved overstays', Icons.history, Colors.grey)
                          : Column(children: _resolved.take(20).map((o) => _buildOverstayCard(o, isResolved: true)).toList()),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          if (_isLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildEmpty(String msg, IconData icon, Color color) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Icon(icon, color: color, size: 40),
        const SizedBox(height: 10),
        Text(msg, style: TextStyle(color: color, fontSize: 13)),
      ]),
    );
  }

  Widget _buildOverstayCard(Map<String, dynamic> o, {bool isResolved = false}) {
    final mins = int.tryParse(o['overstay_minutes']?.toString() ?? '0') ?? 0;
    final hrs = mins ~/ 60;
    final remMins = mins % 60;

    return InkWell(
      onTap: isResolved ? null : () => _showOptions(o),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isResolved ? Colors.grey.shade300 : Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(o['vehicle_number']?.toString() ?? 'N/A', style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isResolved ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isResolved ? 'RESOLVED' : 'ACTIVE', style: TextStyle(color: isResolved ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.timer, color: Colors.red.shade700, size: 14),
              const SizedBox(width: 6),
              Text('Overstay: ${hrs}h ${remMins}m', style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.monetization_on, color: Colors.green.shade700, size: 14),
              const SizedBox(width: 6),
              Text('Extra: ₹${o['extra_amount'] ?? '0'}', style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            Text('Booked end: ${o['booked_end_time'] ?? ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}