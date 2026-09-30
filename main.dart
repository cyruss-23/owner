// main.dart
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized before calling SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();

  // Check if the user is already logged in using your exact existing logic
  bool isLoggedIn = await ApiService.isLoggedIn();

  runApp(OwnerPortalApp(isLoggedIn: isLoggedIn));
}

class OwnerPortalApp extends StatelessWidget {
  final bool isLoggedIn;

  const OwnerPortalApp({Key? key, required this.isLoggedIn}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Park Hub - Owner Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto', // Change this to your preferred font
      ),
      // If logged in, go straight to HomeScreen (it automatically shows the Owner dashboard based on roleId = 3)
      // If not, show the OwnerLoginScreen
      home: isLoggedIn ? const OwnerHomeScreen() : const OwnerLoginScreen(),
    );
  }
}