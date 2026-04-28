import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

const _googleServerClientId =
    '481929024343-f6ar478mu0uconqjospg3ijps85uavd1.apps.googleusercontent.com';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sprint',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Google Sign-In must be initialized before opening the Google login screen.
  // We save the Future so initialization starts once and can be awaited later.
  late final Future<void> _googleSignInReady;

  // Null means no user is signed in yet. After login, this holds the email.
  String? _signedInEmail;

  // Used to disable the button while the login flow is already running.
  bool _isSigningIn = false;

  @override
  void initState() {
    super.initState();

    // initState runs once when this screen is created.
    // The serverClientId is the Web Client ID from Google Cloud.
    _googleSignInReady = GoogleSignIn.instance.initialize(
      serverClientId: _googleServerClientId,
    );
  }

  Future<void> _googleLogin() async {
    // Prevent starting another login while the current one is still running.
    if (_isSigningIn) return;

    if (_googleServerClientId.isEmpty) {
      _showMessage('Missing GOOGLE_SERVER_CLIENT_ID');
      return;
    }

    // setState tells Flutter to rebuild the screen with the new value.
    setState(() {
      _isSigningIn = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting Google login...'),
      ),
    );

    try {
      // Wait until Google Sign-In finished its one-time setup.
      await _googleSignInReady;

      // Opens the Google account picker/sign-in screen.
      final googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: const <String>['email', 'profile'],
      );

      // After an await, check that this screen still exists before using context
      // or setState.
      if (!mounted) return;
      setState(() {
        _signedInEmail = googleUser.email;
      });
      _showMessage('Signed in with Google as ${googleUser.email}');
    } catch (error) {
      debugPrint('Login failed: $error');
      if (!mounted) return;
      _showMessage('Login failed: $error');
    } finally {
      // This runs after success or failure, so the button becomes enabled again.
      if (!mounted) return;
      setState(() {
        _isSigningIn = false;
      });
    }
  }

  void _showMessage(String message) {
    // SnackBar is a temporary message shown at the bottom of the screen.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Sign in to start playing',
              style: TextStyle(
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 24),

            // Only show this text after Google login gives us an email.
            if (_signedInEmail != null) ...[
              Text('Google user: $_signedInEmail'),
              const SizedBox(height: 16),
            ],

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
