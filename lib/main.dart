import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nakama/nakama.dart' as nakama;

const _googleServerClientId =
    '481929024343-f6ar478mu0uconqjospg3ijps85uavd1.apps.googleusercontent.com';
const _nakamaHost = '10.0.2.2';
const _nakamaGrpcPort = 7349;
const _nakamaServerKey = 'defaultkey';
const _nakamaUseSsl = false;
const _playerProfileCollection = 'player';
const _playerProfileKey = 'profile';

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
      final displayName = googleUser.displayName ?? 'Player';

      await _nakamaClient.updateAccount(
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
              nakamaClient: _nakamaClient,
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

enum BackendStatus { checking, connected, failed }

enum ProfileStatus { loading, loaded, failed }

class PlayerProfile {
  const PlayerProfile({
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.bestTimeMs,
    required this.createdAt,
  });

  final int gamesPlayed;
  final int wins;
  final int losses;
  final int? bestTimeMs;
  final String createdAt;

  factory PlayerProfile.createDefault() {
    return PlayerProfile(
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      bestTimeMs: null,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      gamesPlayed: _readInt(json['gamesPlayed']),
      wins: _readInt(json['wins']),
      losses: _readInt(json['losses']),
      bestTimeMs: json['bestTimeMs'] == null
          ? null
          : _readInt(json['bestTimeMs']),
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gamesPlayed': gamesPlayed,
      'wins': wins,
      'losses': losses,
      'bestTimeMs': bestTimeMs,
      'createdAt': createdAt,
    };
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.email,
    required this.displayName,
    required this.nakamaClient,
    required this.nakamaSession,
  });

  final String email;
  final String displayName;
  final nakama.NakamaBaseClient nakamaClient;
  final nakama.Session nakamaSession;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  BackendStatus _backendStatus = BackendStatus.checking;
  ProfileStatus _profileStatus = ProfileStatus.loading;
  PlayerProfile? _playerProfile;

  @override
  void initState() {
    super.initState();
    _checkBackend();
    _loadOrCreatePlayerProfile();
  }

  Future<void> _checkBackend() async {
    try {
      await widget.nakamaClient.rpc(
        session: widget.nakamaSession,
        id: 'healthcheck',
        payload: '',
      );

      if (!mounted) return;
      setState(() {
        _backendStatus = BackendStatus.connected;
      });
    } catch (error) {
      debugPrint('Backend healthcheck failed: $error');
      if (!mounted) return;
      setState(() {
        _backendStatus = BackendStatus.failed;
      });
    }
  }

  Future<void> _loadOrCreatePlayerProfile() async {
    try {
      final objects = await widget.nakamaClient.readStorageObjects(
        session: widget.nakamaSession,
        objectIds: const [
          nakama.StorageObjectId(
            collection: _playerProfileCollection,
            key: _playerProfileKey,
          ),
        ],
      );

      final PlayerProfile profile;
      if (objects.isEmpty) {
        profile = PlayerProfile.createDefault();

        await widget.nakamaClient.writeStorageObjects(
          session: widget.nakamaSession,
          objects: [
            nakama.StorageObjectWrite(
              collection: _playerProfileCollection,
              key: _playerProfileKey,
              value: jsonEncode(profile.toJson()),
              permissionRead: nakama.StorageReadPermission.ownerRead,
              permissionWrite: nakama.StorageWritePermission.ownerWrite,
            ),
          ],
        );
      } else {
        final json = jsonDecode(objects.first.value) as Map<String, dynamic>;
        profile = PlayerProfile.fromJson(json);
      }

      if (!mounted) return;
      setState(() {
        _playerProfile = profile;
        _profileStatus = ProfileStatus.loaded;
      });
    } catch (error) {
      debugPrint('Player profile load failed: $error');
      if (!mounted) return;
      setState(() {
        _profileStatus = ProfileStatus.failed;
      });
    }
  }

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

  Widget _buildBackendStatus(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (_backendStatus) {
      case BackendStatus.checking:
        return _BackendStatusPanel(
          backgroundColor: colorScheme.surfaceContainerHighest,
          foregroundColor: colorScheme.onSurfaceVariant,
          leading: const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: 'Checking backend...',
        );
      case BackendStatus.connected:
        return _BackendStatusPanel(
          backgroundColor: Colors.green.shade50,
          foregroundColor: Colors.green.shade800,
          leading: const Icon(Icons.check_circle, size: 20),
          label: 'Backend connected',
        );
      case BackendStatus.failed:
        return _BackendStatusPanel(
          backgroundColor: colorScheme.errorContainer,
          foregroundColor: colorScheme.onErrorContainer,
          leading: const Icon(Icons.error, size: 20),
          label: 'Backend unavailable',
        );
    }
  }

  Widget _buildProfileStats(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (_profileStatus) {
      case ProfileStatus.loading:
        return _ProfileStatusPanel(
          leading: const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: 'Loading profile...',
          foregroundColor: colorScheme.onSurfaceVariant,
          borderColor: colorScheme.outlineVariant,
        );
      case ProfileStatus.failed:
        return _buildProfileErrorPanel(colorScheme);
      case ProfileStatus.loaded:
        final profile = _playerProfile;
        if (profile == null) {
          return _buildProfileErrorPanel(colorScheme);
        }

        final bestTime = profile.bestTimeMs == null
            ? '-'
            : '${profile.bestTimeMs} ms';

        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile stats',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text('Games played: ${profile.gamesPlayed}'),
                const SizedBox(height: 6),
                Text('Wins: ${profile.wins}'),
                const SizedBox(height: 6),
                Text('Best time: $bestTime'),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildProfileErrorPanel(ColorScheme colorScheme) {
    return _ProfileStatusPanel(
      leading: const Icon(Icons.error, size: 20),
      label: 'Could not load profile',
      foregroundColor: colorScheme.onErrorContainer,
      borderColor: colorScheme.errorContainer,
      backgroundColor: colorScheme.errorContainer,
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
                'Welcome, ${widget.displayName}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(widget.email),
              const SizedBox(height: 20),
              _buildProfileStats(context),
              const SizedBox(height: 28),
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
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: _buildBackendStatus(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackendStatusPanel extends StatelessWidget {
  const _BackendStatusPanel({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.leading,
    required this.label,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: foregroundColor),
              child: leading,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatusPanel extends StatelessWidget {
  const _ProfileStatusPanel({
    required this.leading,
    required this.label,
    required this.foregroundColor,
    required this.borderColor,
    this.backgroundColor,
  });

  final Widget leading;
  final String label;
  final Color foregroundColor;
  final Color borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconTheme(
              data: IconThemeData(color: foregroundColor),
              child: leading,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
