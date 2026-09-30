import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'api_service.dart';

class OwnerWalkinScreen extends StatefulWidget {
  const OwnerWalkinScreen({Key? key}) : super(key: key);

  @override
  State<OwnerWalkinScreen> createState() => _OwnerWalkinScreenState();
}

class _OwnerWalkinScreenState extends State<OwnerWalkinScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _ownerId;
  String _userEmail = '';

  List<dynamic> _parkings = [];
  List<dynamic> _walkins = [];
  List<dynamic> _slots = [];

  final _vehicleNumCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _selectedParkingId = '';
  String _selectedVehicleType = 'car';
  String _selectedSlotId = '';
  String _paymentMode = 'cash';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _vehicleNumCtrl.dispose();
    _mobileCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final session = await ApiService.getUserSession();
      _userEmail = session['email']?.toString() ?? '';

      final responses = await Future.wait([
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_space_owners')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_spaces')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=walkin_entries')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=parking_slots')),
      ]);

      if (mounted) {
        final ownersData = json.decode(responses[0].body);
        final parkingsData = json.decode(responses[1].body);
        final walkinsData = json.decode(responses[2].body);
        final slotsData = json.decode(responses[3].body);

        if (ownersData['status'] == true && ownersData['data'] != null) {
          for (var owner in ownersData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase()) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
        }

        if (_ownerId != null) {
          List<String> myParkingIds = [];
          if (parkingsData['status'] == true && parkingsData['data'] != null) {
            _parkings = (parkingsData['data'] as List).where((p) => p['owner_id'].toString() == _ownerId).toList();
            myParkingIds = _parkings.map((p) => p['id'].toString()).toList();
          }

          if (slotsData['status'] == true && slotsData['data'] != null) {
            _slots = slotsData['data'];
          }

          if (walkinsData['status'] == true && walkinsData['data'] != null) {
            final allWalkins = walkinsData['data'] as List;
            _walkins = allWalkins.where((w) => myParkingIds.contains(w['parking_id'].toString())).toList();
            _walkins.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addWalkin() async {
    if (_vehicleNumCtrl.text.isEmpty || _selectedParkingId.isEmpty) {
      _showSnackBar('Please enter vehicle number and select parking.', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final response = await http.post(
        Uri.parse('https://parkfro.com/API.php?table=walkin_entries'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'parking_id': _selectedParkingId,
          'owner_id': _ownerId ?? '1',
          'vehicle_number': _vehicleNumCtrl.text.trim().toUpperCase(),
          'vehicle_type': _selectedVehicleType,
          'slot_id': _selectedSlotId.isNotEmpty ? _selectedSlotId : '',
          'customer_mobile': _mobileCtrl.text.trim(),
          'entry_time': now,
          'amount': _amountCtrl.text.isNotEmpty ? _amountCtrl.text : '0',
          'payment_mode': _paymentMode,
          'payment_status': _paymentMode == 'pending' ? 'pending' : 'paid',
          'status': 'parked',
        },
      );

      if (response.statusCode == 200) {
        _showSnackBar('Walk-in entry added successfully!', Colors.green);
        _vehicleNumCtrl.clear();
        _mobileCtrl.clear();
        _amountCtrl.clear();
        _selectedSlotId = '';
        _fetchData();
      } else {
        _showSnackBar('Failed to add walk-in entry.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exitWalkin(Map<String, dynamic> walkin) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Mark Exit', style: TextStyle(color: Colors.black)),
        content: Text('Confirm exit for ${walkin['vehicle_number']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Exit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final response = await http.put(
        Uri.parse('https://parkfro.com/API.php?table=walkin_entries'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': walkin['id'].toString(),
          'exit_time': now,
          'status': 'exited',
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar('Exit recorded successfully!', Colors.green);
        _fetchData();
      } else {
        _showSnackBar('Failed to record exit.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
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
                    Icon(Icons.directions_car, color: Colors.blue, size: 28),
                    SizedBox(width: 12),
                    Text('Walk-in Entry', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Register vehicles not booked through app', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

                // Entry Form
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('New Walk-in Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      const SizedBox(height: 20),

                      _buildDropdown('Parking Space *', _selectedParkingId, [
                        {'value': '', 'label': 'Select Parking'},
                        ..._parkings.map((p) => {'value': p['id'].toString(), 'label': p['name'] ?? 'Unknown'})
                      ], (val) => setState(() => _selectedParkingId = val!)),

                      const SizedBox(height: 16),

                      _buildTextField('Vehicle Number *', _vehicleNumCtrl, 'e.g. MH49AB1234'),

                      const SizedBox(height: 16),

                      _buildDropdown('Vehicle Type *', _selectedVehicleType, [
                        {'value': 'car', 'label': 'Car'},
                        {'value': 'bike', 'label': 'Bike'},
                        {'value': 'suv', 'label': 'SUV'},
                        {'value': 'ev', 'label': 'EV'},
                        {'value': 'commercial', 'label': 'Commercial'},
                      ], (val) => setState(() => _selectedVehicleType = val!)),

                      const SizedBox(height: 16),

                      _buildDropdown('Assign Slot (Optional)', _selectedSlotId, [
                        {'value': '', 'label': 'Auto / None'},
                        ..._slots.where((s) => s['parking_id'].toString() == _selectedParkingId && s['status'] == 'available').map((s) => {'value': s['id'].toString(), 'label': s['slot_number'] ?? 'Slot'})
                      ], (val) => setState(() => _selectedSlotId = val!)),

                      const SizedBox(height: 16),

                      _buildTextField('Customer Mobile (Optional)', _mobileCtrl, '10-digit number', keyboardType: TextInputType.phone),

                      const SizedBox(height: 16),

                      _buildTextField('Amount (₹)', _amountCtrl, '0.00', keyboardType: TextInputType.number),

                      const SizedBox(height: 16),

                      _buildDropdown('Payment Mode', _paymentMode, [
                        {'value': 'cash', 'label': 'Cash'},
                        {'value': 'upi', 'label': 'UPI'},
                        {'value': 'online', 'label': 'Online'},
                        {'value': 'pending', 'label': 'Pay at Exit'},
                      ], (val) => setState(() => _paymentMode = val!)),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _addWalkin,
                          icon: _isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.add, color: Colors.white),
                          label: Text(_isSaving ? 'Saving...' : 'Add Walk-in Entry', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Recent Walk-ins
                Row(
                  children: [
                    const Icon(Icons.history, color: Colors.blue, size: 22),
                    const SizedBox(width: 10),
                    const Text('Recent Walk-ins', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                      child: Text(_walkins.length.toString(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                    : _walkins.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                  child: Center(child: Text('No walk-in entries yet', style: TextStyle(color: Colors.grey.shade600))),
                )
                    : Column(children: _walkins.map((w) => _buildWalkinCard(w)).toList()),

                const SizedBox(height: 30),
              ],
            ),
          ),
          if (_isLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildWalkinCard(Map<String, dynamic> walkin) {
    final isParked = walkin['status'] == 'parked';
    final entryTime = walkin['entry_time']?.toString().split('.')[0] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isParked ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(walkin['vehicle_number'] ?? 'N/A', style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isParked ? Colors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isParked ? 'PARKED' : 'EXITED',
                  style: TextStyle(color: isParked ? Colors.green.shade700 : Colors.grey.shade700, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${walkin['vehicle_type']?.toString().toUpperCase() ?? ''} • Entry: $entryTime', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Amount: ₹${walkin['amount'] ?? '0'} • ${walkin['payment_mode']?.toString().toUpperCase() ?? ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          if (isParked) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _exitWalkin(walkin),
                icon: const Icon(Icons.exit_to_app, color: Colors.white, size: 16),
                label: const Text('MARK EXIT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, String hint, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500),
            filled: true, fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<Map<String, String>> options, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value.isEmpty && options.first['value'] == '' ? '' : (value.isEmpty ? null : value),
              isExpanded: true,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Colors.black, fontSize: 14),
              items: options.map((opt) => DropdownMenuItem(value: opt['value'], child: Text(opt['label'] ?? ''))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}