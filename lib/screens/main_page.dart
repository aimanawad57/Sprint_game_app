import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../models/player_profile.dart';
import '../services/nakama_service.dart';
import '../widgets/backend_status_panel.dart';
import 'login_screen.dart';
import 'play_page.dart';
import 'profile_page.dart';

enum BackendStatus { checking, connected, failed }

class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.email,
    required this.displayName,
    required this.nakamaService,
    required this.nakamaSession,
  });

  final String email;
  final String displayName;
  final NakamaService nakamaService;
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
      await widget.nakamaService.checkBackend(widget.nakamaSession);

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
      final profile = await widget.nakamaService.loadOrCreatePlayerProfile(
        widget.nakamaSession,
      );

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

  Future<void> _openPlayPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return PlayPage(
            nakamaService: widget.nakamaService,
            nakamaSession: widget.nakamaSession,
          );
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      _profileStatus = ProfileStatus.loading;
    });
    await _loadOrCreatePlayerProfile();
  }

  void _openProfilePage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return ProfilePage(
            displayName: widget.displayName,
            email: widget.email,
            profile: _playerProfile,
            profileStatus: _profileStatus,
          );
        },
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await widget.nakamaService.closeRealtimeSocket();
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
        return BackendStatusPanel(
          backgroundColor: colorScheme.surfaceContainerHighest,
          foregroundColor: colorScheme.onSurfaceVariant,
          leading: const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: 'Checking backend...',
        );
      case BackendStatus.connected:
        return BackendStatusPanel(
          backgroundColor: Colors.green.shade50,
          foregroundColor: Colors.green.shade800,
          leading: const Icon(Icons.check_circle, size: 20),
          label: 'Backend connected',
        );
      case BackendStatus.failed:
        return BackendStatusPanel(
          backgroundColor: colorScheme.errorContainer,
          foregroundColor: colorScheme.onErrorContainer,
          leading: const Icon(Icons.error, size: 20),
          label: 'Backend unavailable',
        );
    }
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
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _openPlayPage,
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
                onPressed: _openProfilePage,
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
