import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'api_service.dart';

class OwnerSlotMapScreen extends StatefulWidget {
  const OwnerSlotMapScreen({Key? key}) : super(key: key);

  @override
  State<OwnerSlotMapScreen> createState() => _OwnerSlotMapScreenState();
}

class _OwnerSlotMapScreenState extends State<OwnerSlotMapScreen> {
  bool _isLoading = true;
  String? _ownerId;
  String _userEmail = '';

  List<dynamic> _parkings = [];
  List<dynamic> _slots = [];
  String _selectedParkingId = '';

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
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_slots')),
      ]);

      if (mounted) {
        final ownersData = json.decode(responses[0].body);
        final parkingsData = json.decode(responses[1].body);
        final slotsData = json.decode(responses[2].body);

        if (ownersData['status'] == true && ownersData['data'] != null) {
          for (var owner in ownersData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase()) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
        }

        if (_ownerId != null && parkingsData['status'] == true && parkingsData['data'] != null) {
          _parkings = (parkingsData['data'] as List).where((p) => p['owner_id'].toString() == _ownerId).toList();
          if (_parkings.isNotEmpty && _selectedParkingId.isEmpty) {
            _selectedParkingId = _parkings.first['id'].toString();
          }
        }

        if (slotsData['status'] == true && slotsData['data'] != null) {
          _slots = slotsData['data'];
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filteredSlots {
    return _slots.where((s) => s['parking_id'].toString() == _selectedParkingId).toList();
  }

  Future<void> _updateSlotStatus(Map<String, dynamic> slot, String newStatus) async {
    try {
      final response = await http.put(
        Uri.parse('https://parkfro.com/API.php?table=parking_slots'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'id': slot['id'].toString(), 'status': newStatus}),
      );

      if (response.statusCode == 200) {
        _showSnackBar('Slot ${slot['slot_number']} set to ${newStatus.toUpperCase()}', Colors.green);
        _fetchData();
      } else {
        _showSnackBar('Failed to update slot.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
    }
  }

  void _showSlotOptions(Map<String, dynamic> slot) {
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
            Text('Slot ${slot['slot_number']}', style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Type: ${slot['slot_type']?.toString().toUpperCase() ?? 'N/A'} • Current: ${slot['status']?.toString().toUpperCase() ?? 'N/A'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 20),
            const Text('Change Status To:', style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 12,
              children: [
                _buildOptionChip(ctx, slot, 'available', Colors.green),
                _buildOptionChip(ctx, slot, 'occupied', Colors.red),
                _buildOptionChip(ctx, slot, 'reserved', Colors.orange),
                _buildOptionChip(ctx, slot, 'blocked', Colors.grey),
                _buildOptionChip(ctx, slot, 'maintenance', Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionChip(BuildContext ctx, Map<String, dynamic> slot, String status, Color color) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _updateSlotStatus(slot, status);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.4))),
        child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Color _getSlotColor(String status) {
    switch (status) {
      case 'available': return Colors.green;
      case 'occupied': return Colors.red;
      case 'reserved': return Colors.orange;
      case 'blocked': return Colors.grey;
      case 'maintenance': return Colors.purple;
      default: return Colors.grey;
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
                    Icon(Icons.grid_view, color: Colors.blue, size: 28),
                    SizedBox(width: 12),
                    Text('Slot Map', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Tap any slot to change its status', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

                // Parking Selector
                if (_parkings.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedParkingId.isEmpty ? null : _selectedParkingId,
                        isExpanded: true,
                        dropdownColor: Colors.white,
                        style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600),
                        items: _parkings.map((p) => DropdownMenuItem(value: p['id'].toString(), child: Text(p['name'] ?? 'Unknown'))).toList(),
                        onChanged: (val) => setState(() => _selectedParkingId = val!),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Legend
                Wrap(
                  spacing: 16, runSpacing: 8,
                  children: [
                    _buildLegend('Available', Colors.green),
                    _buildLegend('Occupied', Colors.red),
                    _buildLegend('Reserved', Colors.orange),
                    _buildLegend('Blocked', Colors.grey),
                    _buildLegend('Maintenance', Colors.purple),
                  ],
                ),
                const SizedBox(height: 24),

                // Slot Grid
                _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                    : _filteredSlots.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                  child: Center(child: Text('No slots defined for this parking.\nAdd slots from the API or Parking screen.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600))),
                )
                    : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: _filteredSlots.length,
                  itemBuilder: (context, index) {
                    final slot = _filteredSlots[index];
                    final color = _getSlotColor(slot['status']?.toString().toLowerCase() ?? 'available');
                    return InkWell(
                      onTap: () => _showSlotOptions(slot),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: color, width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              slot['slot_number'] ?? '?',
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              slot['status']?.toString().toUpperCase() ?? '',
                              style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
          if (_isLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
      ],
    );
  }
}