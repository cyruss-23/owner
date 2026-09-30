import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'api_service.dart';

class OwnerMoneyScreen extends StatefulWidget {
  const OwnerMoneyScreen({Key? key}) : super(key: key);

  @override
  State<OwnerMoneyScreen> createState() => _OwnerMoneyScreenState();
}

class _OwnerMoneyScreenState extends State<OwnerMoneyScreen> {
  bool _isLoading = true;
  String? _ownerId;
  String _userEmail = '';

  List<dynamic> _parkings = [];
  List<dynamic> _walkins = [];
  List<dynamic> _bookings = [];

  double _todayCash = 0;
  double _todayUpi = 0;
  double _todayOnline = 0;
  double _todayTotal = 0;
  double _monthRevenue = 0;
  double _lifetimeRevenue = 0;

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
        http.get(Uri.parse('https://parkfro.com/API.php?table=walkin_entries')),
        http.get(Uri.parse('https://parkfro.com/API.php?table=bookings')),
      ]);

      if (mounted) {
        final ownersData = json.decode(responses[0].body);
        final parkingsData = json.decode(responses[1].body);
        final walkinsData = json.decode(responses[2].body);
        final bookingsData = json.decode(responses[3].body);

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
            _parkings = (parkingsData['data'] as List)
                .where((p) => p['owner_id'].toString() == _ownerId)
                .toList();
            myParkingIds = _parkings.map((p) => p['id'].toString()).toList();
          }

          if (walkinsData['status'] == true && walkinsData['data'] != null) {
            _walkins = (walkinsData['data'] as List)
                .where((w) => myParkingIds.contains(w['parking_id'].toString()))
                .toList();
          }

          if (bookingsData['status'] == true && bookingsData['data'] != null) {
            _bookings = (bookingsData['data'] as List)
                .where((b) => myParkingIds.contains(b['parking_id'].toString()))
                .toList();
          }

          _calculateStats();
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateStats() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final thisMonth = DateFormat('yyyy-MM').format(DateTime.now());

    _todayCash = 0;
    _todayUpi = 0;
    _todayOnline = 0;
    _monthRevenue = 0;
    _lifetimeRevenue = 0;

    // Calculate from walk-ins
    for (var w in _walkins) {
      final amount = double.tryParse(w['amount']?.toString() ?? '0') ?? 0;
      final entryDate = w['entry_time']?.toString().split(' ')[0] ?? '';
      final paymentMode = w['payment_mode']?.toString().toLowerCase() ?? '';

      _lifetimeRevenue += amount;

      if (entryDate.startsWith(thisMonth)) _monthRevenue += amount;

      if (entryDate == today) {
        if (paymentMode == 'cash') _todayCash += amount;
        else if (paymentMode == 'upi') _todayUpi += amount;
        else if (paymentMode == 'online') _todayOnline += amount;
      }
    }

    // Calculate from bookings
    for (var b in _bookings) {
      final amount = double.tryParse(b['total_amount']?.toString() ?? '0') ?? 0;
      final bookingDate = b['booking_date']?.toString() ?? '';
      final payStatus = b['payment_status']?.toString().toLowerCase() ?? '';

      if (payStatus == 'paid') {
        _lifetimeRevenue += amount;
        if (bookingDate.startsWith(thisMonth)) _monthRevenue += amount;
        if (bookingDate == today) {
          _todayOnline += amount;
        }
      }
    }

    _todayTotal = _todayCash + _todayUpi + _todayOnline;
    if (mounted) setState(() {});
  }

  String _formatCurrency(double amount) {
    if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₹${amount.toStringAsFixed(0)}';
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
          RefreshIndicator(
            onRefresh: _fetchData,
            color: Colors.blue,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet, color: Colors.blue, size: 28),
                      SizedBox(width: 12),
                      Text('Money', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Revenue, payments and settlements', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 24),

                  // Today's Total Hero Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.black, Colors.grey.shade900],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("TODAY'S COLLECTION", style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        Text('₹${_todayTotal.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _buildHeroStat('Cash', _todayCash, Icons.payments),
                            const SizedBox(width: 20),
                            _buildHeroStat('UPI', _todayUpi, Icons.qr_code),
                            const SizedBox(width: 20),
                            _buildHeroStat('Online', _todayOnline, Icons.credit_card),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Summary Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard('This Month', _formatCurrency(_monthRevenue), Icons.calendar_month, Colors.blue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard('Lifetime', _formatCurrency(_lifetimeRevenue), Icons.trending_up, Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Settlement Preview
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
                        Row(
                          children: [
                            const Icon(Icons.receipt_long, color: Colors.orange, size: 22),
                            const SizedBox(width: 10),
                            const Text('Settlement Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSettlementRow('Gross Revenue', _monthRevenue, false),
                        _buildSettlementRow('Commission (10%)', _monthRevenue * 0.10, true),
                        _buildSettlementRow('GST (18%)', _monthRevenue * 0.018, true),
                        const Divider(height: 24),
                        _buildSettlementRow('Net Payable', _monthRevenue - (_monthRevenue * 0.118), false, isBold: true),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_empty, color: Colors.orange.shade700, size: 16),
                              const SizedBox(width: 8),
                              Text('Settlement Status: PENDING', style: TextStyle(color: Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Actions
                  const Text('Quick Actions', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickAction(
                          'Cash Entry',
                          Icons.add_card,
                          Colors.green,
                              () => _showCashEntryDialog(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickAction(
                          'Day Closing',
                          Icons.event_available,
                          Colors.blue,
                              () => _showDayClosingDialog(),
                        ),
                      ),
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

  Widget _buildHeroStat(String label, double amount, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey.shade400, size: 14),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text('₹${amount.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSettlementRow(String label, double amount, bool isDeduction, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isDeduction ? Colors.red.shade700 : Colors.grey.shade700, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${isDeduction ? '- ' : ''}₹${amount.toStringAsFixed(2)}',
            style: TextStyle(color: isDeduction ? Colors.red.shade700 : Colors.black, fontSize: isBold ? 15 : 13, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showCashEntryDialog() {
    final cashCtrl = TextEditingController();
    final upiCtrl = TextEditingController();
    final onlineCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Record Cash Collection', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogInput('Cash Amount (₹)', cashCtrl, '0.00'),
              const SizedBox(height: 12),
              _buildDialogInput('UPI Amount (₹)', upiCtrl, '0.00'),
              const SizedBox(height: 12),
              _buildDialogInput('Online Amount (₹)', onlineCtrl, '0.00'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () async {
              if (cashCtrl.text.isEmpty && upiCtrl.text.isEmpty && onlineCtrl.text.isEmpty) {
                _showSnackBar('Enter at least one amount.', Colors.orange);
                return;
              }

              try {
                final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                final cash = double.tryParse(cashCtrl.text) ?? 0;
                final upi = double.tryParse(upiCtrl.text) ?? 0;
                final online = double.tryParse(onlineCtrl.text) ?? 0;

                await http.post(
                  Uri.parse('https://parkfro.com/API.php?table=cash_collections'),
                  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                  body: {
                    'parking_id': _parkings.isNotEmpty ? _parkings.first['id'].toString() : '1',
                    'owner_id': _ownerId ?? '1',
                    'collection_date': today,
                    'cash_amount': cash.toString(),
                    'upi_amount': upi.toString(),
                    'online_amount': online.toString(),
                    'total_amount': (cash + upi + online).toString(),
                  },
                );

                Navigator.pop(ctx);
                _showSnackBar('Cash collection recorded!', Colors.green);
                _fetchData();
              } catch (e) {
                _showSnackBar('Failed to record.', Colors.red);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDayClosingDialog() {
    final todayWalkins = _walkins.where((w) {
      final entryDate = w['entry_time']?.toString().split(' ')[0] ?? '';
      return entryDate == DateFormat('yyyy-MM-dd').format(DateTime.now());
    }).toList();

    final parked = _walkins.where((w) => w['status'] == 'parked').length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Day Closing', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildClosingRow('Total Walk-ins', todayWalkins.length.toString()),
            _buildClosingRow('Still Parked', parked.toString()),
            _buildClosingRow('Cash', '₹${_todayCash.toStringAsFixed(0)}'),
            _buildClosingRow('UPI', '₹${_todayUpi.toStringAsFixed(0)}'),
            _buildClosingRow('Online', '₹${_todayOnline.toStringAsFixed(0)}'),
            const Divider(),
            _buildClosingRow('Total', '₹${_todayTotal.toStringAsFixed(0)}', isBold: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              try {
                final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                await http.post(
                  Uri.parse('https://parkfro.com/API.php?table=daily_closings'),
                  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                  body: {
                    'parking_id': _parkings.isNotEmpty ? _parkings.first['id'].toString() : '1',
                    'closing_date': today,
                    'total_vehicles': todayWalkins.length.toString(),
                    'completed_vehicles': (todayWalkins.length - parked).toString(),
                    'still_parked': parked.toString(),
                    'cash_total': _todayCash.toString(),
                    'upi_total': _todayUpi.toString(),
                    'online_total': _todayOnline.toString(),
                    'grand_total': _todayTotal.toString(),
                    'closed_by': _ownerId ?? '1',
                  },
                );
                Navigator.pop(ctx);
                _showSnackBar('Day closed successfully!', Colors.green);
              } catch (e) {
                _showSnackBar('Failed to close day.', Colors.red);
              }
            },
            child: const Text('CLOSE DAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          Text(value, style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildDialogInput(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500),
            filled: true, fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }
}