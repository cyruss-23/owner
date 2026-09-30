import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'api_service.dart';

class OwnerAnalyticsScreen extends StatefulWidget {
  const OwnerAnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<OwnerAnalyticsScreen> createState() => _OwnerAnalyticsScreenState();
}

class _OwnerAnalyticsScreenState extends State<OwnerAnalyticsScreen> {
  bool _isLoading = true;
  String? _ownerId;
  String _userEmail = '';

  List<dynamic> _parkings = [];
  List<dynamic> _bookings = [];
  List<dynamic> _walkins = [];

  // Period selector
  String _selectedPeriod = 'This Month'; // Today, This Week, This Month, Last Month

  // Stats
  double _todayRevenue = 0;
  double _weekRevenue = 0;
  double _monthRevenue = 0;
  double _lastMonthRevenue = 0;
  double _growthPercent = 0;

  int _todayBookings = 0;
  int _weekBookings = 0;
  int _monthBookings = 0;

  // Monthly chart data
  List<double> _monthlyBookings = List.filled(12, 0);
  List<double> _monthlyRevenue = List.filled(12, 0);

  // Occupancy by day
  List<double> _occupancyByDay = List.filled(7, 0);
  List<int> _dayCounts = List.filled(7, 0);

  // Heat map data (hour buckets)
  List<int> _hourBuckets = List.filled(8, 0); // 0-3, 3-6, 6-9, 9-12, 12-15, 15-18, 18-21, 21-24

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
        http.get(Uri.parse('https://parkfro.com/API.php?table=walkin_entries')),
      ]);

      if (mounted) {
        final ownersData = json.decode(responses[0].body);
        final parkingsData = json.decode(responses[1].body);
        final bookingsData = json.decode(responses[2].body);
        final walkinsData = json.decode(responses[3].body);

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

          if (bookingsData['status'] == true && bookingsData['data'] != null) {
            _bookings = (bookingsData['data'] as List)
                .where((b) => myParkingIds.contains(b['parking_id'].toString()))
                .toList();
          }

          if (walkinsData['status'] == true && walkinsData['data'] != null) {
            _walkins = (walkinsData['data'] as List)
                .where((w) => myParkingIds.contains(w['parking_id'].toString()))
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
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final thisMonthStr = DateFormat('yyyy-MM').format(now);
    final lastMonthStr = DateFormat('yyyy-MM').format(DateTime(now.year, now.month - 1, 1));

    // Reset
    _todayRevenue = 0; _weekRevenue = 0; _monthRevenue = 0; _lastMonthRevenue = 0;
    _todayBookings = 0; _weekBookings = 0; _monthBookings = 0;
    _monthlyBookings = List.filled(12, 0);
    _monthlyRevenue = List.filled(12, 0);
    _occupancyByDay = List.filled(7, 0);
    _dayCounts = List.filled(7, 0);
    _hourBuckets = List.filled(8, 0);

    final nowWeekAgo = now.subtract(const Duration(days: 7));

    // Process bookings
    for (var b in _bookings) {
      final amount = double.tryParse(b['total_amount']?.toString() ?? '0') ?? 0;
      final status = b['status']?.toString().toLowerCase() ?? '';
      final payStatus = b['payment_status']?.toString().toLowerCase() ?? '';
      final dateStr = b['booking_date']?.toString() ?? '';

      if (status == 'cancelled' || status == 'no_show') continue;

      DateTime? bDate;
      try { bDate = DateTime.parse(dateStr); } catch (_) {}

      // Revenue aggregates
      if (payStatus == 'paid' || status == 'confirmed' || status == 'completed') {
        if (dateStr == todayStr) {
          _todayRevenue += amount;
          _todayBookings++;
        }
        if (bDate != null && bDate.isAfter(nowWeekAgo)) {
          _weekRevenue += amount;
          _weekBookings++;
        }
        if (dateStr.startsWith(thisMonthStr)) {
          _monthRevenue += amount;
          _monthBookings++;
        }
        if (dateStr.startsWith(lastMonthStr)) {
          _lastMonthRevenue += amount;
        }

        if (bDate != null) {
          _monthlyBookings[bDate.month - 1]++;
          _monthlyRevenue[bDate.month - 1] += amount;
        }
      }

      // Occupancy by day
      if (bDate != null) {
        final weekday = bDate.weekday - 1; // 0=Mon
        if (weekday >= 0 && weekday < 7) {
          _occupancyByDay[weekday] += 1;
          _dayCounts[weekday] += 1;
        }
      }

      // Heat map by start_time hour
      try {
        final startHour = int.parse(b['start_time']?.toString().split(':')[0] ?? '0');
        final bucketIndex = (startHour ~/ 3).clamp(0, 7);
        _hourBuckets[bucketIndex]++;
      } catch (_) {}
    }

    // Process walk-ins
    for (var w in _walkins) {
      final amount = double.tryParse(w['amount']?.toString() ?? '0') ?? 0;
      final entryTime = w['entry_time']?.toString() ?? '';
      final dateStr = entryTime.split(' ').first;

      DateTime? wDate;
      try { wDate = DateTime.parse(dateStr); } catch (_) {}

      if (dateStr == todayStr) { _todayRevenue += amount; _todayBookings++; }
      if (wDate != null && wDate.isAfter(nowWeekAgo)) { _weekRevenue += amount; _weekBookings++; }
      if (dateStr.startsWith(thisMonthStr)) { _monthRevenue += amount; _monthBookings++; }
      if (dateStr.startsWith(lastMonthStr)) { _lastMonthRevenue += amount; }

      if (wDate != null) {
        _monthlyBookings[wDate.month - 1]++;
        _monthlyRevenue[wDate.month - 1] += amount;
        final weekday = wDate.weekday - 1;
        if (weekday >= 0 && weekday < 7) {
          _occupancyByDay[weekday] += 1;
          _dayCounts[weekday] += 1;
        }
      }

      try {
        final entryHour = int.parse(entryTime.split(' ').last.split(':')[0]);
        final bucketIndex = (entryHour ~/ 3).clamp(0, 7);
        _hourBuckets[bucketIndex]++;
      } catch (_) {}
    }

    // Growth
    if (_lastMonthRevenue > 0) {
      _growthPercent = ((_monthRevenue - _lastMonthRevenue) / _lastMonthRevenue) * 100;
    } else if (_monthRevenue > 0) {
      _growthPercent = 100;
    }

    if (mounted) setState(() {});
  }

  double get _periodRevenue {
    switch (_selectedPeriod) {
      case 'Today': return _todayRevenue;
      case 'This Week': return _weekRevenue;
      case 'This Month': return _monthRevenue;
      case 'Last Month': return _lastMonthRevenue;
      default: return _monthRevenue;
    }
  }

  int get _periodBookings {
    switch (_selectedPeriod) {
      case 'Today': return _todayBookings;
      case 'This Week': return _weekBookings;
      case 'This Month': return _monthBookings;
      case 'Last Month': return _monthBookings;
      default: return _monthBookings;
    }
  }

  String _formatCurrency(double amount) {
    if (amount >= 100000) return '₹${(amount / 100000).toStringAsFixed(2)}L';
    if (amount >= 1000) return '₹${(amount / 1000).toStringAsFixed(1)}K';
    return '₹${amount.toStringAsFixed(0)}';
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
                  const Row(
                    children: [
                      Icon(Icons.analytics, color: Colors.blue, size: 28),
                      SizedBox(width: 12),
                      Text('Analytics', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Occupancy, revenue and peak hour insights', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 20),

                  // Period Selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['Today', 'This Week', 'This Month', 'Last Month'].map((p) {
                        final isSelected = _selectedPeriod == p;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: InkWell(
                            onTap: () => setState(() => _selectedPeriod = p),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.black : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isSelected ? Colors.black : Colors.grey.shade300),
                              ),
                              child: Text(p, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Hero Revenue Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.black, Colors.grey.shade900]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_selectedPeriod REVENUE', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(_periodRevenue), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _growthPercent >= 0 ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_growthPercent >= 0 ? Icons.trending_up : Icons.trending_down, color: _growthPercent >= 0 ? Colors.green : Colors.red, size: 14),
                                  const SizedBox(width: 4),
                                  Text('${_growthPercent.toStringAsFixed(1)}% vs last month', style: TextStyle(color: _growthPercent >= 0 ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('$_periodBookings bookings', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Occupancy Section
                  _buildSectionTitle('OCCUPANCY BY DAY', Icons.calendar_view_week, Colors.blue),
                  const SizedBox(height: 12),
                  _buildOccupancyChart(),
                  const SizedBox(height: 24),

                  // Revenue Chart
                  _buildSectionTitle('MONTHLY REVENUE', Icons.monetization_on, Colors.green),
                  const SizedBox(height: 12),
                  _buildRevenueChart(),
                  const SizedBox(height: 24),

                  // Heat Map
                  _buildSectionTitle('PEAK PARKING HOURS', Icons.local_fire_department, Colors.orange),
                  const SizedBox(height: 12),
                  _buildHeatMap(),
                  const SizedBox(height: 24),

                  // Summary Cards
                  Row(
                    children: [
                      Expanded(child: _buildSummaryCard('Today', _formatCurrency(_todayRevenue), '$_todayBookings bookings', Icons.today, Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSummaryCard('This Week', _formatCurrency(_weekRevenue), '$_weekBookings bookings', Icons.date_range, Colors.purple)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildSummaryCard('This Month', _formatCurrency(_monthRevenue), '$_monthBookings bookings', Icons.calendar_month, Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSummaryCard('Last Month', _formatCurrency(_lastMonthRevenue), '—', Icons.history, Colors.grey)),
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

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildOccupancyChart() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxVal = _occupancyByDay.isEmpty ? 1.0 : _occupancyByDay.reduce((a, b) => a > b ? a : b);
    final double maxH = 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
      child: SizedBox(
        height: 160,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (i) {
            final val = _occupancyByDay[i];
            final h = maxVal > 0 ? (val / maxVal) * maxH : 4.0;
            final dayName = days[i];
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(val.toInt().toString(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: val > 0 ? Colors.blue : Colors.transparent)),
                const SizedBox(height: 4),
                Container(
                  width: 20, height: h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.blue.withOpacity(0.3), Colors.blue]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(dayName, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildRevenueChart() {
    final months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final maxVal = _monthlyRevenue.isEmpty ? 1.0 : _monthlyRevenue.reduce((a, b) => a > b ? a : b);
    final double maxH = 90;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(12, (i) {
            final val = _monthlyRevenue[i];
            final h = maxVal > 0 ? (val / maxVal) * maxH : 4.0;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (val > 0)
                  Text(_formatCurrency(val).replaceAll('₹', ''), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                const SizedBox(height: 4),
                Container(
                  width: 12, height: h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.green.withOpacity(0.3), Colors.green]),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(months[i], style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHeatMap() {
    final labels = ['12-3am', '3-6am', '6-9am', '9-12pm', '12-3pm', '3-6pm', '6-9pm', '9-12am'];
    final maxVal = _hourBuckets.isEmpty ? 1 : _hourBuckets.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: List.generate(8, (i) {
          final count = _hourBuckets[i];
          final intensity = maxVal > 0 ? (count / maxVal) : 0.0;
          final color = Color.lerp(Colors.grey.shade200, Colors.orange, intensity.toDouble()) ?? Colors.grey.shade200;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 70, child: Text(labels[i], style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 30, child: Text(count.toString(), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
        ],
      ),
    );
  }
}