import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nakama/nakama.dart' as nakama;

const _googleServerClientId =
    '481929024343-f6ar478mu0uconqjospg3ijps85uavd1.apps.googleusercontent.com';
const _nakamaHost = '10.0.2.2';
const _nakamaGrpcPort = 7349;
const _nakamaServerKey = 'defaultkey';
const _nakamaUseSsl = false;

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

  // This client is how Flutter talks to the Nakama server.
  late final nakama.NakamaBaseClient _nakamaClient;

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

    // Android emulator uses 10.0.2.2 to reach localhost on your computer.
    _nakamaClient = nakama.getNakamaClient(
      host: _nakamaHost,
      grpcPort: _nakamaGrpcPort,
      serverKey: _nakamaServerKey,
      ssl: _nakamaUseSsl,
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
      // Later, this is the kind of token we will send to Nakama.
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      // Do not print the actual token because tokens are private.
      debugPrint('Has Google ID token: ${idToken != null}');

      if (idToken == null) {
        throw Exception('Google ID token is missing');
      }

      final session = await _nakamaClient.authenticateGoogle(token: idToken);

      // After an await, check that this screen still exists before using context
      // or setState.
      if (!mounted) return;
      loginSucceeded = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) {
            return MainPage(
              email: googleUser.email,
              displayName: googleUser.displayName ?? 'Player',
              nakamaUserId: session.userId,
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
      if (!mounted || loginSucceeded) return;
      setState(() {
        _isSigningIn = false;
      });
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

            const Text(
              'Sign in to start playing',
              style: TextStyle(fontSize: 16),
            ),

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

class MainPage extends StatelessWidget {
  const MainPage({
    super.key,
    required this.email,
    required this.displayName,
    required this.nakamaUserId,
  });

  final String email;
  final String displayName;
  final String nakamaUserId;

  void _showComingSoon(BuildContext context, String featureName) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$featureName will be added later')));
  }

  Future<void> _signOut(BuildContext context) async {
    await GoogleSignIn.instance.signOut();

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) {
          return const LoginScreen();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sprint'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome, $displayName',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(email),
              const SizedBox(height: 8),
              Text(
                'Nakama user id: $nakamaUserId',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => _showComingSoon(context, 'Play'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showComingSoon(context, 'Leaderboard'),
                icon: const Icon(Icons.leaderboard),
                label: const Text('Leaderboard'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showComingSoon(context, 'Profile'),
                icon: const Icon(Icons.person),
                label: const Text('Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
