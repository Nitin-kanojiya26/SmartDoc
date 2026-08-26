import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartdoc/screens/login_screen.dart';
import 'package:smartdoc/screens/home_screen.dart';
import 'package:smartdoc/services/auth_service.dart';
import 'package:smartdoc/theme/app_theme.dart';
import 'package:smartdoc/theme/theme_service.dart';
import 'firebase_options.dart';
import 'package:smartdoc/screens/document_detail_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization error: $e');
  }
  runApp(const SmartDocApp());
}

class SmartDocApp extends StatelessWidget {
  const SmartDocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return MaterialApp(
          title: 'SmartDoc',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeService.themeMode,
          debugShowCheckedModeBanner: false,
          home: const AuthWrapper(),
        );
      }
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    return StreamBuilder<User?>(
      stream: authService.user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Auth Error: ${snapshot.error}')));
        }
        
        if (snapshot.hasData) {
          return FutureBuilder<bool>(
            future: authService.isSessionValid(),
            builder: (context, sessionSnapshot) {
              if (sessionSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (sessionSnapshot.hasError) {
                // If session check fails, default to login for safety
                return const LoginScreen();
              }
              if (sessionSnapshot.data == true) {
                return const HomeScreen();
              }
              return const LoginScreen();
            },
          );
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}