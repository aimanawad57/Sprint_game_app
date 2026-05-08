import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/nakama_config.dart';
import '../services/nakama_service.dart';
import 'main_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Google Sign-In must be initialized before opening the Google login screen.
  // We save the Future so initialization starts once and can be awaited later.
  late final Future<void> _googleSignInReady;

  // This service owns the Nakama client and backend calls.
  late final NakamaService _nakamaService;

  // Used to disable the button while the login flow is already running.
  bool _isSigningIn = false;

  @override
  void initState() {
    super.initState();

    // initState runs once when this screen is created.
    // The serverClientId is the Web Client ID from Google Cloud.
    _googleSignInReady = GoogleSignIn.instance.initialize(
      serverClientId: googleServerClientId,
    );

    _nakamaService = NakamaService();
  }

  Future<void> _googleLogin() async {
    // Prevent starting another login while the current one is still running.
    if (_isSigningIn) return;

    if (googleServerClientId.isEmpty) {
      _showMessage('Missing GOOGLE_SERVER_CLIENT_ID');
      return;
    }

    // setState tells Flutter to rebuild the screen with the new value.
    setState(() {
      _isSigningIn = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Starting Google login...')));

    var loginSucceeded = false;

    try {
      // Wait until Google Sign-In finished its one-time setup.
      await _googleSignInReady;

      // Opens the Google account picker/sign-in screen.
      final googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: const <String>['email', 'profile'],
      );
      debugPrint('Google user email: ${googleUser.email}');
      debugPrint('Google user display name: ${googleUser.displayName}');
      debugPrint('Google user id: ${googleUser.id}');

      // The ID token is proof from Google that this user signed in.
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      // Do not print the actual token because tokens are private.
      debugPrint('Has Google ID token: ${idToken != null}');

      if (idToken == null) {
        throw Exception('Google ID token is missing');
      }

      final session = await _nakamaService.authenticateWithGoogle(idToken);
      final displayName = googleUser.displayName ?? 'Player';

      await _nakamaService.updateDisplayName(
        session: session,
        displayName: displayName,
      );

      // After an await, check that this screen still exists before using context
      // or setState.
      if (!mounted) return;
      loginSucceeded = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) {
            return MainPage(
              email: googleUser.email,
              displayName: displayName,
              nakamaService: _nakamaService,
              nakamaSession: session,
            );
          },
        ),
      );
    } catch (error) {
      debugPrint('Login failed: $error');
      if (!mounted) return;
      _showMessage('Login failed: $error');
    } finally {
      // This runs after success or failure, so the button becomes enabled again.
      if (mounted && !loginSucceeded) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    // SnackBar is a temporary message shown at the bottom of the screen.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Sprint',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text('Sign in to start playing', style: TextStyle(fontSize: 16)),

            const SizedBox(height: 24),

            FilledButton(
              // null disables the button while login is running.
              onPressed: _isSigningIn ? null : _googleLogin,
              child: Text(
                _isSigningIn ? 'Signing in...' : 'Continue with Google',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
