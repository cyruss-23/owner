import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'api_service.dart';

class OwnerAvailabilityScreen extends StatefulWidget {
  const OwnerAvailabilityScreen({Key? key}) : super(key: key);

  @override
  State<OwnerAvailabilityScreen> createState() => _OwnerAvailabilityScreenState();
}

class _OwnerAvailabilityScreenState extends State<OwnerAvailabilityScreen> {
  bool _isLoading = true;
  List<dynamic> _parkings = [];
  String? _ownerId;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _fetchParkings();
  }

  Future<void> _fetchParkings() async {
    setState(() => _isLoading = true);
    try {
      final session = await ApiService.getUserSession();
      _userEmail = session['email']?.toString() ?? '';

      final ownerRes = await http.get(Uri.parse('https://parkfro.com/API.php?table=parking_space_owners'));
      if (ownerRes.statusCode == 200) {
        final ownerData = json.decode(ownerRes.body);
        if (ownerData['status'] == true && ownerData['data'] != null) {
          for (var owner in ownerData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase()) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
        }
      }

      if (_ownerId != null) {
        final parkingRes = await http.get(Uri.parse('https://parkfro.com/API.php?table=parking_spaces'));
        if (parkingRes.statusCode == 200) {
          final parkingData = json.decode(parkingRes.body);
          if (parkingData['status'] == true && parkingData['data'] != null) {
            final allSpaces = parkingData['data'] as List;
            setState(() {
              _parkings = allSpaces.where((p) => p['owner_id'].toString() == _ownerId).toList();
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error loading parkings.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> parking, String status, {int? durationHours}) async {
    try {
      final uri = Uri.parse('https://parkfro.com/API.php?table=parking_spaces');
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': parking['id'].toString(),
          'status': status,
        }),
      );

      if (response.statusCode == 200) {
        // Log the status change
        await http.post(
          Uri.parse('https://parkfro.com/API.php?table=parking_status_log'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'parking_id': parking['id'].toString(),
            'status': status,
            'duration_hours': durationHours?.toString() ?? '',
            'changed_by': _ownerId ?? '1',
          },
        );

        _showSnackBar('Status updated to ${status.toUpperCase()}', Colors.green);
        _fetchParkings();
      } else {
        _showSnackBar('Failed to update status.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
    }
  }

  void _showDurationDialog(Map<String, dynamic> parking, String status) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Set $status Duration', style: const TextStyle(color: Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDurationOption(parking, status, 1, '1 Hour'),
            _buildDurationOption(parking, status, 2, '2 Hours'),
            _buildDurationOption(parking, status, 4, '4 Hours'),
            _buildDurationOption(parking, status, 12, '12 Hours'),
            _buildDurationOption(parking, status, 24, '24 Hours'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateStatus(parking, status);
              },
              child: const Text('No Time Limit', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationOption(Map<String, dynamic> parking, String status, int hours, String label) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.black)),
      onTap: () {
        Navigator.pop(context);
        _updateStatus(parking, status, durationHours: hours);
      },
    );
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
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
                    Icon(Icons.toggle_on, color: Colors.blue, size: 28),
                    SizedBox(width: 12),
                    Text('Availability Control', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('One-tap control for your parking status', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

                _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                    : _parkings.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
                  child: const Center(child: Text('No parking spaces found.', style: TextStyle(color: Colors.black54))),
                )
                    : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _parkings.length,
                  itemBuilder: (context, index) => _buildAvailabilityCard(_parkings[index]),
                ),
              ],
            ),
          ),
          if (_isLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard(Map<String, dynamic> parking) {
    final currentStatus = parking['status']?.toString().toLowerCase() ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(parking['name'] ?? 'Unknown', style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(currentStatus).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _getStatusColor(currentStatus).withOpacity(0.4)),
                ),
                child: Text(currentStatus.toUpperCase(), style: TextStyle(color: _getStatusColor(currentStatus), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${parking['address'] ?? ''}, ${parking['city'] ?? ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 20),

          // One-Tap Buttons
          Row(
            children: [
              Expanded(
                child: _buildStatusButton(
                  'OPEN',
                  Icons.check_circle,
                  Colors.green,
                  currentStatus == 'open',
                      () => _updateStatus(parking, 'open'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusButton(
                  'FULL',
                  Icons.block,
                  Colors.red,
                  currentStatus == 'full',
                      () => _showDurationDialog(parking, 'full'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatusButton(
                  'CLOSED',
                  Icons.lock,
                  Colors.grey,
                  currentStatus == 'closed',
                      () => _updateStatus(parking, 'closed'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusButton(
                  'MAINTENANCE',
                  Icons.build,
                  Colors.orange,
                  currentStatus == 'maintenance',
                      () => _showDurationDialog(parking, 'maintenance'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open': return Colors.green;
      case 'full': return Colors.red;
      case 'closed': return Colors.grey;
      case 'maintenance': return Colors.orange;
      case 'approved': return Colors.green;
      case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Widget _buildStatusButton(String label, IconData icon, Color color, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? color : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? Colors.white : color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}