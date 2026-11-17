import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math'; // Added for OTP generation
import 'api_service.dart';
import 'home_screen.dart'; // Ensure this points to OwnerHomeScreen
import 'register_screen.dart';

class OwnerLoginScreen extends StatefulWidget {
  const OwnerLoginScreen({Key? key}) : super(key: key);

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> with SingleTickerProviderStateMixin {
  String? _selectedRoleId;
  List<dynamic> _roles = [];
  bool _isLoadingRoles = true;
  bool _isProcessing = false;

  // New State Variables for OTP Flow
  bool _isOtpSent = false;
  String _generatedOtp = '';
  Map<String, dynamic>? _matchedUser;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
    _loadRoles();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _mobileController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    final roles = await ApiService.fetchRoles();
    if (mounted) {
      setState(() {
        if (roles.isNotEmpty) {
          // FILTER: Only show Parking Space Owner (ID: 3)
          _roles = roles.where((role) => role['id'].toString() == '3').toList();
        } else {
          _roles = [{"id": "3", "role": "Parking Space Owner"}];
        }

        // Auto-select Owner role
        if (_roles.isNotEmpty) {
          _selectedRoleId = _roles.first['id'].toString();
        }
        _isLoadingRoles = false;
      });
    }
  }

  Future<void> _handleAction() async {
    if (!_isOtpSent) {
      await _sendOtp();
    } else {
      await _verifyOtp();
    }
  }

  Future<void> _sendOtp() async {
    final mobile = _mobileController.text.trim();

    if (mobile.isEmpty || mobile.length < 10 || _selectedRoleId == null) {
      _showSnackBar('Please enter a valid 10-digit mobile number.', Colors.red.shade400);
      return;
    }

    setState(() { _isProcessing = true; });

    try {
      // Find if user exists, but DO NOT block the OTP if they are not registered yet
      final user = await ApiService.findUserByMobile(mobile, _selectedRoleId!);

      // Generate a 4-digit random OTP
      String otp = (1000 + Random().nextInt(9000)).toString();

      // Call Fast2SMS API
      bool sent = await ApiService.sendOtp(mobile, otp);

      if (mounted) {
        setState(() { _isProcessing = false; });
        if (sent) {
          setState(() {
            _isOtpSent = true;
            _generatedOtp = otp;
            _matchedUser = user; // Will be null if new user, which is perfectly fine
          });
          _showSnackBar('OTP sent successfully!', Colors.green.shade500);
        } else {
          _showSnackBar('Failed to send OTP. Please try again.', Colors.red.shade400);
        }
      }
    } catch (e) {
      debugPrint('Send OTP error: $e');
      if (mounted) {
        setState(() { _isProcessing = false; });
        _showSnackBar('Error: $e', Colors.red.shade400);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final enteredOtp = _otpController.text.trim();

    if (enteredOtp.isEmpty) {
      _showSnackBar('Please enter the OTP.', Colors.red.shade400);
      return;
    }

    setState(() { _isProcessing = true; });

    if (enteredOtp == _generatedOtp) {
      try {
        if (_matchedUser != null) {
          // USER IS ALREADY REGISTERED -> Check Approval Status
          final email = _matchedUser!['username']?.toString() ?? '';
          final ownerStatus = await ApiService.getOwnerApprovalStatus(email);

          if (mounted) {
            setState(() { _isProcessing = false; });

            // ALLOW BOTH 'APPROVED' AND 'PENDING' TO LOGIN DIRECTLY
            if (ownerStatus == 'approved' || ownerStatus == 'pending' || ownerStatus == null || ownerStatus.isEmpty) {
              await ApiService.createSessionForMobileLogin(_matchedUser!);
              _navigateToHome();
            } else {
              _showSnackBar('Your account has been rejected or disabled.', Colors.red.shade400);
              await ApiService.logout();
            }
          }
        } else {
          // USER IS NEW/NOT REGISTERED -> Redirect to Registration Screen
          if (mounted) {
            final mobileNum = _mobileController.text.trim();
            setState(() {
              _isProcessing = false;
              _isOtpSent = false;
              _otpController.clear();
              _generatedOtp = '';
            });
            _showSnackBar('Number verified! Please complete your registration.', Colors.blue.shade500);

            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => RegisterScreen(mobileNumber: mobileNum)),
            );
          }
        }
      } catch (e) {
        debugPrint('Routing error: $e');
        if (mounted) {
          setState(() { _isProcessing = false; });
          _showSnackBar('An error occurred. Please try again.', Colors.red.shade400);
        }
      }
    } else {
      if (mounted) {
        setState(() { _isProcessing = false; });
        _showSnackBar('Invalid OTP. Please check and try again.', Colors.red.shade400);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const OwnerHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.grey.shade50],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 30.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.black, Colors.grey.shade900],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.garage, color: Colors.black, size: 28),
                        ),
                        const SizedBox(width: 12),
                        const Text('Owner Portal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Welcome Text
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Welcome Partner!', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      Text('Sign in securely with your mobile number', style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w400)),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // Form Inputs dynamically updated based on OTP state
                  if (!_isOtpSent)
                    _buildInputField(
                      controller: _mobileController,
                      hintText: 'Registered Mobile Number',
                      prefixIcon: Icons.phone_android,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                    )
                  else ...[
                    // Read-only Phone Number Display with Edit Button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.phone_android, color: Colors.grey.shade500, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('+91 ${_mobileController.text}', style: TextStyle(fontSize: 16, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isOtpSent = false;
                                _otpController.clear();
                              });
                            },
                            child: const Text('Edit', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildInputField(
                      controller: _otpController,
                      hintText: 'Enter 4-Digit OTP',
                      prefixIcon: Icons.lock_outline,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Role Dropdown (Locked to Owner, removed dropdown icon)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedRoleId,
                      icon: const SizedBox.shrink(), // Removed the dropdown arrow icon
                      decoration: InputDecoration(
                        hintText: _isLoadingRoles ? 'Loading...' : 'Select your role',
                        prefixIcon: Icon(Icons.business_center, color: Colors.grey.shade700, size: 24),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                      items: _isLoadingRoles ? [] : _roles.map<DropdownMenuItem<String>>((role) {
                        return DropdownMenuItem<String>(
                          value: role['id'].toString(),
                          child: Text(role['role'], style: const TextStyle(fontWeight: FontWeight.w600)),
                        );
                      }).toList(),
                      onChanged: null, // Locks the dropdown from being changed
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Login Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        shadowColor: Colors.black.withOpacity(0.3),
                      ),
                      child: _isProcessing
                          ? const SizedBox(height: 26, width: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_isOtpSent ? 'Verify & Login' : 'Send OTP', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward, size: 22),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Sign Up Link (for owners)
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => RegisterScreen(mobileNumber: _mobileController.text.trim())),
                        );
                      },
                      child: RichText(
                        text: TextSpan(
                          text: "Don't have an owner account? ",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                          children: const [
                            TextSpan(text: 'Register manually', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          counterText: '', // Hides the character length counter below field
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          prefixIcon: Icon(prefixIcon, color: Colors.grey.shade600, size: 24),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
