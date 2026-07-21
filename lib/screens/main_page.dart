import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../models/player_profile.dart';
import '../models/play_exit_action.dart';
import '../services/nakama_service.dart';
import '../services/onboarding_progress_repository.dart';
import '../widgets/backend_status_panel.dart';
import '../widgets/disconnected_match_banner.dart';
import 'create_join_match_screen.dart';
import 'leaderboard_page.dart';
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
  String? _resumableMatchId;
  bool _isAbandoningMatch = false;
  late final OnboardingProgressRepository _onboardingRepository;

  @override
  void initState() {
    super.initState();
    _onboardingRepository = OnboardingProgressRepository(
      nakamaService: widget.nakamaService,
      session: widget.nakamaSession,
    );
    _checkBackend();
    _loadOrCreatePlayerProfile();
  }

  Future<void> _checkBackend() async {
    try {
      await widget.nakamaService.checkBackend(widget.nakamaSession);
      await _onboardingRepository.synchronize();

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

  Future<void> _openPlayPage() async {
    final result = await Navigator.of(context).push<PlayExitResult>(
      MaterialPageRoute(
        builder: (context) {
          return CreateJoinMatchScreen(
            nakamaService: widget.nakamaService,
            nakamaSession: widget.nakamaSession,
          );
        },
      ),
    );

    if (!mounted) return;
    _handlePlayExitResult(result);
    if (!mounted) return;
    setState(() {
      _profileStatus = ProfileStatus.loading;
    });
    await _loadOrCreatePlayerProfile();

    if (!mounted) return;
    if (result?.action == PlayExitAction.viewProfile) {
      _openProfilePage();
    }
  }

  Future<void> _reconnectToMatch() async {
    final matchId = _resumableMatchId;
    if (matchId == null) return;

    final result = await Navigator.of(context).push<PlayExitResult>(
      MaterialPageRoute(
        builder: (context) {
          return PlayPage(
            nakamaService: widget.nakamaService,
            nakamaSession: widget.nakamaSession,
            directMatchId: matchId,
          );
        },
      ),
    );

    if (!mounted) return;
    _handlePlayExitResult(result);
    setState(() {
      _profileStatus = ProfileStatus.loading;
    });
    await _loadOrCreatePlayerProfile();

    if (!mounted) return;
    if (result?.action == PlayExitAction.viewProfile) {
      _openProfilePage();
    }
  }

  Future<void> _abandonResumableMatch() async {
    final matchId = _resumableMatchId;
    if (matchId == null || _isAbandoningMatch) return;

    setState(() {
      _isAbandoningMatch = true;
    });

    try {
      await widget.nakamaService.abandonAuthoritativeMatch(
        session: widget.nakamaSession,
        matchId: matchId,
      );

      if (!mounted) return;
      setState(() {
        _resumableMatchId = null;
        _profileStatus = ProfileStatus.loading;
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _loadOrCreatePlayerProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Match abandoned.')));
    } catch (error) {
      debugPrint('Could not abandon match: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not abandon the match.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAbandoningMatch = false;
        });
      }
    }
  }

  void _handlePlayExitResult(PlayExitResult? result) {
    if (result?.action == PlayExitAction.disconnectedFromMatch) {
      setState(() {
        _resumableMatchId = result?.matchId;
      });
      return;
    }

    if (result?.action == PlayExitAction.viewProfile ||
        result?.action == PlayExitAction.matchFinished) {
      setState(() {
        _resumableMatchId = null;
      });
    }
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

  void _openLeaderboardPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return LeaderboardPage(
            nakamaService: widget.nakamaService,
            nakamaSession: widget.nakamaSession,
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
              if (_resumableMatchId != null) ...[
                DisconnectedMatchBanner(
                  onReconnect: _reconnectToMatch,
                  onAbandon: _isAbandoningMatch ? null : _abandonResumableMatch,
                  isAbandoning: _isAbandoningMatch,
                ),
                const SizedBox(height: 20),
              ],
              FilledButton.icon(
                onPressed: _openPlayPage,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openLeaderboardPage,
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
