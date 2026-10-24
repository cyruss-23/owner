import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';

import 'api_service.dart';

class OwnerQrScreen extends StatefulWidget {
  const OwnerQrScreen({Key? key}) : super(key: key);

  @override
  State<OwnerQrScreen> createState() => _OwnerQrScreenState();
}

class _OwnerQrScreenState extends State<OwnerQrScreen> {
  bool _isLoading = true;
  String? _ownerId;
  String _userEmail = '';
  List<dynamic> _parkings = [];
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
      ]);

      if (mounted) {
        final ownersData = json.decode(responses[0].body);
        final parkingsData = json.decode(responses[1].body);

        if (ownersData['status'] == true && ownersData['data'] != null) {
          for (var owner in ownersData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase()) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
        }

        if (_ownerId != null && parkingsData['status'] == true && parkingsData['data'] != null) {
          _parkings = (parkingsData['data'] as List)
              .where((p) => p['owner_id'].toString() == _ownerId)
              .toList();
          if (_parkings.isNotEmpty && _selectedParkingId.isEmpty) {
            _selectedParkingId = _parkings.first['id'].toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? get _selectedParking {
    if (_selectedParkingId.isEmpty) return null;
    try {
      return _parkings.firstWhere((p) => p['id'].toString() == _selectedParkingId);
    } catch (_) {
      return null;
    }
  }

  String _buildQrPayload(Map<String, dynamic> parking) {
    // Format: PARKFRO|PARKING_ID|OWNER_ID|NAME
    return 'PARKFRO|${parking['id']}|${_ownerId ?? '0'}|${parking['name'] ?? ''}';
  }

  void _copyQrData() {
    final parking = _selectedParking;
    if (parking == null) return;
    final payload = _buildQrPayload(parking);
    Clipboard.setData(ClipboardData(text: payload));
    _showSnackBar('QR data copied to clipboard!', Colors.green);
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
        backgroundColor: Colors.white, elevation: 0,
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
                    Icon(Icons.qr_code_2, color: Colors.blue, size: 28),
                    SizedBox(width: 12),
                    Text('Parking QR Code', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Customer scans this QR to check-in at your parking', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

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

                _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                    : _parkings.isEmpty
                    ? _buildEmptyState('No parking spaces available')
                    : _selectedParking == null
                    ? _buildEmptyState('Select a parking space above')
                    : _buildQrCard(_selectedParking!),

                const SizedBox(height: 24),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text('How it works', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionStep('1', 'Print and display this QR at your parking entrance'),
                      _buildInstructionStep('2', 'Customer scans the QR using their app'),
                      _buildInstructionStep('3', 'System identifies the parking + booking'),
                      _buildInstructionStep('4', 'Owner receives automatic check-in notification'),
                    ],
                  ),
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

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Icon(Icons.qr_code, color: Colors.grey.shade400, size: 40),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildQrCard(Map<String, dynamic> parking) {
    final payload = _buildQrPayload(parking);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
            child: const Text('SCAN TO PARK', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
          const SizedBox(height: 20),

          // Parking Name
          Text(parking['name'] ?? 'Parking', style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('${parking['address'] ?? ''}, ${parking['city'] ?? ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 24),

          // ✅ QR CODE — using real qr_flutter package
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Parking ID badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text('PARKING ID: ${parking['id']}', style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 24),

          // Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _copyQrData,
                  icon: const Icon(Icons.copy, color: Colors.white, size: 16),
                  label: const Text('Copy Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showQrPayloadDialog(payload),
                  icon: const Icon(Icons.code, color: Colors.black, size: 16),
                  label: const Text('View Data', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  void _showQrPayloadDialog(String payload) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('QR Payload', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data encoded in this QR:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(payload, style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(11)),
            child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: Colors.blue.shade900, fontSize: 13))),
        ],
      ),
    );
  }
}


class _QrPainter extends CustomPainter {
  final String data;
  _QrPainter({required this.data});

  static const int _gridSize = 25;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _gridSize;
    final paint = Paint()..color = Colors.black;
    final bg = Paint()..color = Colors.white;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    // Deterministic matrix from data hash
    final bytes = utf8.encode(data);
    for (int y = 0; y < _gridSize; y++) {
      for (int x = 0; x < _gridSize; x++) {
        final idx = (y * _gridSize + x) % bytes.length;
        final val = (bytes[idx] + x * 7 + y * 13) % 3;
        if (val == 0) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }

    // Finder patterns (3 corners)
    _drawFinder(canvas, 0, 0, cell, paint);
    _drawFinder(canvas, (_gridSize - 7) * cell, 0, cell, paint);
    _drawFinder(canvas, 0, (_gridSize - 7) * cell, cell, paint);
  }

  void _drawFinder(Canvas canvas, double ox, double oy, double cell, Paint paint) {
    canvas.drawRect(Rect.fromLTWH(ox, oy, cell * 7, cell * 7), paint);
    final white = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(ox + cell, oy + cell, cell * 5, cell * 5), white);
    canvas.drawRect(Rect.fromLTWH(ox + cell * 2, oy + cell * 2, cell * 3, cell * 3), paint);
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.data != data;
}
