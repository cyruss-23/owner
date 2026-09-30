import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({Key? key}) : super(key: key);

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  String? _ownerId;
  String? _kycId;
  String _kycStatus = 'NOT SUBMITTED';

  // Form Controllers
  final _aadhaarCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();

  // Selected Files
  File? _aadhaarPhoto;
  File? _panPhoto;

  // Existing Photo URLs from API
  String? _existingAadhaarUrl;
  String? _existingPanUrl;

  @override
  void initState() {
    super.initState();
    _fetchKycData();
  }

  @override
  void dispose() {
    _aadhaarCtrl.dispose();
    _panCtrl.dispose();
    _bankCtrl.dispose();
    _ifscCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchKycData() async {
    setState(() => _isLoading = true);

    try {
      final sessionResponse = await http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=parking_space_owners'));

      if (sessionResponse.statusCode == 200) {
        final ownerData = json.decode(sessionResponse.body);
        if (ownerData['status'] == true && ownerData['data'] != null) {
          if (ownerData['data'].isNotEmpty) {
            _ownerId = ownerData['data'][0]['id'].toString();
          }
        }
      }

      if (_ownerId != null) {
        final kycResponse = await http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=owner_kyc'));
        if (kycResponse.statusCode == 200) {
          final kycData = json.decode(kycResponse.body);
          if (kycData['status'] == true && kycData['data'] != null) {

            final myKyc = (kycData['data'] as List).firstWhere(
                    (k) => k['owner_id'].toString() == _ownerId,
                orElse: () => null
            );

            if (myKyc != null) {
              if (mounted) {
                setState(() {
                  _kycId = myKyc['id'].toString();
                  _kycStatus = myKyc['status']?.toString().toUpperCase() ?? 'PENDING';
                  _aadhaarCtrl.text = myKyc['aadhaar_number']?.toString() ?? '';
                  _panCtrl.text = myKyc['pan_number']?.toString() ?? '';
                  _bankCtrl.text = myKyc['bank_account']?.toString() ?? '';
                  _ifscCtrl.text = myKyc['ifsc_code']?.toString() ?? '';
                  _existingAadhaarUrl = myKyc['aadhaar_photo'];
                  _existingPanUrl = myKyc['pan_photo'];
                });
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching KYC: $e');
      _showSnackBar('Failed to load KYC data.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitKyc() async {
    if (_aadhaarCtrl.text.isEmpty || _panCtrl.text.isEmpty || _bankCtrl.text.isEmpty || _ifscCtrl.text.isEmpty) {
      _showSnackBar('Please fill all required text fields.', Colors.orange);
      return;
    }

    if (_kycId == null && (_aadhaarPhoto == null || _panPhoto == null)) {
      _showSnackBar('Please upload both ID photos.', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uri = Uri.parse('https://parkfro.com/API.php/API.php?table=owner_kyc');

      // --- SCENARIO 1: TEXT-ONLY UPDATE ---
      // If updating existing KYC and NO new files are selected, use standard JSON PUT to prevent 500 error.
      if (_kycId != null && _aadhaarPhoto == null && _panPhoto == null) {
        final response = await http.put(
          uri,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: json.encode({
            'id': _kycId,
            'owner_id': _ownerId ?? '1',
            'aadhaar_number': _aadhaarCtrl.text,
            'pan_number': _panCtrl.text,
            'bank_account': _bankCtrl.text,
            'ifsc_code': _ifscCtrl.text,
            'status': 'pending', // Resubmit sets status back to pending
          }),
        );

        if (response.statusCode == 200) {
          _showSnackBar('KYC updated successfully!', Colors.green);
          await _fetchKycData();
        } else {
          _showSnackBar('Server Error: ${response.statusCode}', Colors.red);
        }
        return; // Stop execution here
      }

      // --- SCENARIO 2: UPLOADING/UPDATING FILES ---
      // PHP doesn't process files on PUT. So we DELETE the old record, then immediately POST a new one.
      if (_kycId != null) {
        await http.delete(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'id': _kycId}),
        );
      }

      // Create a brand new POST request (No 'id' field passed to prevent duplicate entry 500 error)
      var request = http.MultipartRequest('POST', uri);

      request.fields['owner_id'] = _ownerId ?? '1';
      request.fields['aadhaar_number'] = _aadhaarCtrl.text;
      request.fields['pan_number'] = _panCtrl.text;
      request.fields['bank_account'] = _bankCtrl.text;
      request.fields['ifsc_code'] = _ifscCtrl.text;
      request.fields['status'] = 'pending';

      // Attach new files OR send the old string URL back so it isn't lost
      if (_aadhaarPhoto != null) {
        request.files.add(await http.MultipartFile.fromPath('aadhaar_photo', _aadhaarPhoto!.path));
      } else if (_existingAadhaarUrl != null) {
        request.fields['aadhaar_photo'] = _existingAadhaarUrl!;
      }

      if (_panPhoto != null) {
        request.files.add(await http.MultipartFile.fromPath('pan_photo', _panPhoto!.path));
      } else if (_existingPanUrl != null) {
        request.fields['pan_photo'] = _existingPanUrl!;
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['status'] == true || responseData['message'] == 'Created Successfully' || responseData['message'] == 'Updated Successfully') {
          _showSnackBar('KYC submitted successfully!', Colors.green);
          await _fetchKycData(); // Reload to get updated status and images
        } else {
          _showSnackBar(responseData['message'] ?? 'Failed to submit KYC.', Colors.orange.shade700);
        }
      } else {
        _showSnackBar('Server Error: ${response.statusCode}', Colors.red);
      }
    } catch (e) {
      debugPrint('Error submitting KYC: $e');
      _showSnackBar('Error connecting to server.', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    setState(() {
      _aadhaarCtrl.clear();
      _panCtrl.clear();
      _bankCtrl.clear();
      _ifscCtrl.clear();
      _aadhaarPhoto = null;
      _panPhoto = null;
    });
  }

  Future<void> _pickImage(bool isAadhaar) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          if (isAadhaar) {
            _aadhaarPhoto = File(pickedFile.path);
            _existingAadhaarUrl = null;
          } else {
            _panPhoto = File(pickedFile.path);
            _existingPanUrl = null;
          }
        });
      }
    } catch (e) {
      _showSnackBar('Error picking image. Permission denied.', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    Color statusColor = Colors.grey;
    if (_kycStatus == 'APPROVED') statusColor = Colors.green;
    if (_kycStatus == 'PENDING') statusColor = Colors.orange;
    if (_kycStatus == 'REJECTED') statusColor = Colors.red;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.grey.shade50,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _isLoading || _isSaving,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.verified_user, color: Colors.blue, size: 28),
                          SizedBox(width: 12),
                          Text('KYC Verification', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: statusColor.withOpacity(0.5))),
                        child: Text(_kycStatus, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Submit your documents for owner verification', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 24),

                  if (_kycId != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _kycStatus == 'REJECTED' ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kycStatus == 'REJECTED' ? Colors.red.withOpacity(0.3) : Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              _kycStatus == 'REJECTED' ? Icons.error_outline : Icons.info_outline,
                              color: _kycStatus == 'REJECTED' ? Colors.red : Colors.blue,
                              size: 24
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _kycStatus == 'REJECTED'
                                  ? 'Your previous KYC was rejected. Please correct your details and resubmit.'
                                  : 'Your KYC is currently $_kycStatus. Updating these details will require admin re-verification.',
                              style: TextStyle(
                                  color: _kycStatus == 'REJECTED' ? Colors.red.shade700 : Colors.blue.shade700,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResponsiveRow(
                          isMobile,
                          _buildInputField('ID Number *', _aadhaarCtrl, 'Enter 12 digits without spaces', isNumber: true),
                          _buildInputField('PAN Number *', _panCtrl, 'Format: 5 letters, 4 digits, 1 letter'),
                        ),
                        const SizedBox(height: 24),

                        _buildResponsiveRow(
                          isMobile,
                          _buildInputField('Bank Account Number *', _bankCtrl, 'Enter your bank account number', isNumber: true),
                          _buildInputField('IFSC Code *', _ifscCtrl, 'Format: 4 letters, 0, 6 alphanumeric characters'),
                        ),
                        const SizedBox(height: 24),

                        const Text('ID Photo (Front) *', style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _buildImageUploadBox(true, _aadhaarPhoto, _existingAadhaarUrl),
                        const SizedBox(height: 24),

                        const Text('PAN Photo *', style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _buildImageUploadBox(false, _panPhoto, _existingPanUrl),

                        const SizedBox(height: 32),
                        Divider(color: Colors.grey.shade200, thickness: 1),
                        const SizedBox(height: 20),

                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isSaving ? null : _submitKyc,
                              icon: _isSaving
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.upload_file, color: Colors.white, size: 20),
                              label: Text(
                                  _isSaving ? 'Submitting...' : (_kycId != null ? 'Resubmit / Update KYC' : 'Submit for Verification'),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            if (_kycId == null)
                              OutlinedButton.icon(
                                onPressed: _resetForm,
                                icon: const Icon(Icons.refresh, color: Colors.black, size: 18),
                                label: const Text('Reset', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey.shade300),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          if (_isLoading)
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(backgroundColor: Colors.grey.shade200, color: Colors.blue, minHeight: 3),
            ),
        ],
      ),
    );
  }

  Widget _buildImageUploadBox(bool isAadhaar, File? selectedFile, String? existingUrl) {
    bool hasFile = selectedFile != null || (existingUrl != null && existingUrl.isNotEmpty);

    return InkWell(
      onTap: () => _pickImage(isAadhaar),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile ? Colors.green : Colors.grey.shade300,
            style: BorderStyle.solid,
            width: hasFile ? 2 : 1,
          ),
          image: selectedFile != null
              ? DecorationImage(
              image: FileImage(selectedFile),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken)
          )
              : (existingUrl != null && existingUrl.isNotEmpty
              ? DecorationImage(
              image: NetworkImage('https://parkfro.com/API.php/$existingUrl'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken)
          )
              : null),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                hasFile ? Icons.check_circle : Icons.insert_drive_file,
                color: hasFile ? Colors.green : Colors.grey.shade400,
                size: 36
            ),
            const SizedBox(height: 12),
            Text(
              hasFile ? (selectedFile != null ? 'New file selected (Tap to change)' : 'Document uploaded (Tap to change)') : 'Click to upload ${isAadhaar ? 'ID' : 'PAN'} photo',
              style: TextStyle(color: hasFile ? Colors.white : Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (!hasFile) ...[
              const SizedBox(height: 6),
              Text('JPEG, PNG (Max 2MB)', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveRow(bool isMobile, Widget field1, Widget field2) {
    if (isMobile) {
      return Column(children: [field1, const SizedBox(height: 16), field2]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: field1), const SizedBox(width: 16), Expanded(child: field2)]);
  }

  Widget _buildInputField(String label, TextEditingController controller, String helper, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            hintText: helper.startsWith('Enter') || helper.startsWith('Format') ? helper : null,
            hintStyle: TextStyle(color: Colors.grey.shade500),
            filled: true, fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 4),
        if (!helper.startsWith('Enter') && !helper.startsWith('Format'))
          Text(helper, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }
}