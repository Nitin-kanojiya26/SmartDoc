import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get user => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Save login timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_login_time', DateTime.now().millisecondsSinceEpoch);
      
      return credential.user;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<User?> registerWithEmail(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save login timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_login_time', DateTime.now().millisecondsSinceEpoch);

      return credential.user;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<bool> isSessionValid() async {
    if (_auth.currentUser == null) return false;
    
    final prefs = await SharedPreferences.getInstance();
    final lastLogin = prefs.getInt('last_login_time') ?? 0;
    
    if (lastLogin == 0) return true; // Legacy session, let it pass once

    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDays = 30 * 24 * 60 * 60 * 1000;
    
    if (now - lastLogin > thirtyDays) {
      await signOut();
      return false;
    }
    return true;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_login_time');
    await _auth.signOut();
  }

  String _handleError(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No user found with this email.';
        case 'wrong-password':
          return 'Incorrect password.';
        case 'email-already-in-use':
          return 'Email already in use.';
        case 'weak-password':
          return 'Password is too weak.';
        case 'invalid-email':
          return 'Invalid email address.';
        default:
          return 'Authentication error: ${error.message}';
      }
    }
    // Non-Firebase error (network, etc.)
    return 'Something went wrong: $error';
  }
}