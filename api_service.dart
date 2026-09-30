import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://parkfro.com/API.php';
  static const String rolesUrl = '$baseUrl/API.php?table=admin_roles';
  static const String loginUrl = '$baseUrl/API.php?action=login';
  static const String registerUrl = '$baseUrl/API.php?table=users1';
  static const String bookingsUrl = '$baseUrl/API.php?table=bookings';
  static const String parkingSpacesUrl = '$baseUrl/API.php?table=parking_spaces';
  static const String parkingSpaceOwnersUrl = '$baseUrl/API.php?table=parking_space_owners';

  static const String keyIsLoggedIn = 'isLoggedIn';
  static const String keyUserEmail = 'userEmail';
  static const String keyUserRoleId = 'userRoleId';
  static const String keyUserFullName = 'userFullName';
  static const String keyUserId = 'userId';

  // Fast2SMS API Key
  static const String fast2smsKey = 'ZKGPi7qtcjY4bfk3VT8NSuJX95LwBA2vghRWdaDQeFsO0IlrHxxXUAvm41Q0gSceM6R8PiFLKp7bqOVn';

  static Future<List<dynamic>> fetchRoles() async {
    try {
      final response = await http.get(Uri.parse(rolesUrl));
      debugPrint('Roles API Response: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic>) {
          if (data['status'] == true && data['data'] is List) {
            return data['data'] as List<dynamic>;
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching roles: $e");
    }

    return [
      {"id": "1", "role": "Super Admin"},
      {"id": "2", "role": "Drive / Customer"},
      {"id": "3", "role": "Parking Space Owner"}
    ];
  }

  static Future<bool> login({
    required String email,
    required String password,
    required String roleId,
  }) async {
    try {
      debugPrint('Login attempt with email: $email, roleId: $roleId');

      final response = await http.post(
        Uri.parse(loginUrl),
        body: {
          'username': email,
          'password': password,
          'role_id': roleId,
        },
      );

      debugPrint('Login API Response: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic> && data['status'] == true) {
          final userData = data['data'];

          dynamic user;
          if (userData is List && userData.isNotEmpty) {
            user = userData[0];
          } else if (userData is Map<String, dynamic>) {
            user = userData;
          }

          final fullName = user?['full_name']?.toString() ?? 'User';
          final userId = user?['id']?.toString() ?? '';

          await _saveUserSession(
            email: email,
            roleId: roleId,
            fullName: fullName,
            userId: userId,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint("Login API Error: $e");
    }
    return false;
  }

  // --- UPDATED REGISTER LOGIC TO INSERT INTO parking_space_owners ---
  static Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required String mobileNumber,
    required String roleId,
  }) async {
    try {
      debugPrint('Register attempt with email: $email, roleId: $roleId');

      // 1. Insert into users1 table
      final response = await http.post(
        Uri.parse(registerUrl),
        body: {
          'full_name': fullName,
          'username': email,
          'mobile_number': mobileNumber,
          'password': password,
          'role_id': roleId,
          'status': '1',
        },
      );

      debugPrint('Register API Response (users1): ${response.body}');

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic>) {
          if (data['status'] == true || data['message'] == 'Success') {

            // 2. If the new user is an Owner (Role 3), link them in parking_space_owners
            if (roleId == '3') {
              try {
                // Short delay to ensure the database has finalized the users1 insertion
                await Future.delayed(const Duration(milliseconds: 500));

                // Fetch the newly created user to get their auto-generated 'user_id'
                final newUser = await findUserByMobile(mobileNumber, roleId);
                final newUserId = newUser != null ? (newUser['id']?.toString() ?? '') : '';

                // Insert into parking_space_owners table
                final ownerInsertResponse = await http.post(
                  Uri.parse(parkingSpaceOwnersUrl),
                  body: {
                    'user_id': newUserId,
                    'full_name': fullName,
                    'email': email,
                    'phone': mobileNumber,
                    'status': 'pending', // Default status for new owners
                  },
                );

                debugPrint('Owner Link Insert Response: ${ownerInsertResponse.body}');
              } catch (e) {
                debugPrint('Failed to insert into parking_space_owners: $e');
                // We still return true below because the main account was created
              }
            }

            return true;
          }
        }
      }
    } catch (e) {
      debugPrint("Register API Error: $e");
    }
    return false;
  }

  static Future<Map<String, dynamic>> fetchBookings() async {
    try {
      final response = await http.get(Uri.parse(bookingsUrl));
      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return {'status': false, 'data': [], 'message': 'Invalid response'};
    } catch (e) {
      return {'status': false, 'data': [], 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> fetchParkingSpaces() async {
    try {
      final response = await http.get(Uri.parse(parkingSpacesUrl));
      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return {'status': false, 'data': [], 'message': 'Invalid response'};
    } catch (e) {
      return {'status': false, 'data': [], 'message': e.toString()};
    }
  }

  static Future<String?> getOwnerApprovalStatus(String email) async {
    try {
      final response = await http.get(Uri.parse(parkingSpaceOwnersUrl));
      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['status'] == true && data['data'] != null) {
          final owners = data['data'] as List;

          for (var owner in owners) {
            final ownerEmail = owner['email']?.toString().toLowerCase() ?? '';
            if (ownerEmail == email.toLowerCase()) {
              return owner['status']?.toString().toLowerCase() ?? '';
            }
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, String?>> getLoggedInUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'id': prefs.getString(keyUserId),
        'email': prefs.getString(keyUserEmail),
        'roleId': prefs.getString(keyUserRoleId),
        'fullName': prefs.getString(keyUserFullName),
      };
    } catch (e) {
      return {'id': null, 'email': null, 'roleId': null, 'fullName': null};
    }
  }

  static Future<void> _saveUserSession({
    required String email,
    required String roleId,
    required String fullName,
    String userId = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyIsLoggedIn, true);
      await prefs.setString(keyUserEmail, email);
      await prefs.setString(keyUserRoleId, roleId);
      await prefs.setString(keyUserFullName, fullName);
      if (userId.isNotEmpty) {
        await prefs.setString(keyUserId, userId);
      }
    } catch (e) {
      debugPrint("Error saving session: $e");
    }
  }

  static Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyIsLoggedIn) ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, String?>> getUserSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'email': prefs.getString(keyUserEmail),
        'roleId': prefs.getString(keyUserRoleId),
        'fullName': prefs.getString(keyUserFullName),
        'userId': prefs.getString(keyUserId),
      };
    } catch (e) {
      return {'email': null, 'roleId': null, 'fullName': null, 'userId': null};
    }
  }

  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyIsLoggedIn);
      await prefs.remove(keyUserEmail);
      await prefs.remove(keyUserRoleId);
      await prefs.remove(keyUserFullName);
      await prefs.remove(keyUserId);
    } catch (e) {
      debugPrint("Error during logout: $e");
    }
  }

  // ==========================================
  // MOBILE NUMBER & OTP LOGIC FOR OWNERS
  // ==========================================

  static Future<Map<String, dynamic>?> findUserByMobile(String mobileNumber, String roleId) async {
    try {
      // Using the exact URL provided for users1 logic
      final response = await http.get(Uri.parse('https://parkfro.com/API.php/API.php?table=users1'));
      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['status'] == true && data['data'] != null) {
          final users = data['data'] as List;

          for (var user in users) {
            if (user['mobile_number'] == mobileNumber && user['role_id'].toString() == roleId) {
              return user;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error finding user by mobile: $e");
    }
    return null;
  }

  static Future<bool> sendOtp(String mobileNumber, String otp) async {
    try {
      final url = 'https://www.fast2sms.com/dev/bulkV2?authorization=$fast2smsKey&route=dlt&sender_id=Skyeat&message=181220&variables_values=$otp&flash=0&numbers=$mobileNumber';

      final response = await http.get(Uri.parse(url));
      debugPrint('Fast2SMS API Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['return'] == true;
      }
    } catch (e) {
      debugPrint("Error sending OTP via Fast2SMS: $e");
    }
    return false;
  }

  static Future<void> createSessionForMobileLogin(Map<String, dynamic> user) async {
    final email = user['username']?.toString() ?? user['email']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? 'Owner';
    final roleId = user['role_id']?.toString() ?? '3';
    final userId = user['id']?.toString() ?? '';

    await _saveUserSession(
      email: email,
      roleId: roleId,
      fullName: fullName,
      userId: userId,
    );
  }
}