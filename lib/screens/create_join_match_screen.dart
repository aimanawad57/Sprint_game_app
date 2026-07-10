import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../models/play_exit_action.dart';
import '../services/nakama_service.dart';
import 'play_page.dart';

class CreateJoinMatchScreen extends StatefulWidget {
  const CreateJoinMatchScreen({
    super.key,
    required this.nakamaService,
    required this.nakamaSession,
  });

  final NakamaService nakamaService;
  final nakama.Session nakamaSession;

  @override
  State<CreateJoinMatchScreen> createState() => _CreateJoinMatchScreenState();
}

class _CreateJoinMatchScreenState extends State<CreateJoinMatchScreen> {
  final _codeController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openQuickMatch() async {
    final result = await Navigator.of(context).push<PlayExitResult>(
      MaterialPageRoute(
        builder: (context) {
          return PlayPage(
            nakamaService: widget.nakamaService,
            nakamaSession: widget.nakamaSession,
          );
        },
      ),
    );

    _bubblePlayResult(result);
  }

  Future<void> _createMatch() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    try {
      final created = await widget.nakamaService.createMatchByCode(
        widget.nakamaSession,
      );

      if (!mounted) return;
      final result = await Navigator.of(context).push<PlayExitResult>(
        MaterialPageRoute(
          builder: (context) {
            return PlayPage(
              nakamaService: widget.nakamaService,
              nakamaSession: widget.nakamaSession,
              directMatchId: created.matchId,
              displayCode: created.code,
            );
          },
        ),
      );
      _bubblePlayResult(result);
    } catch (error) {
      debugPrint('Could not create match: $error');
      if (!mounted) return;
      _showMessage('Could not create a match. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _joinMatch() async {
    if (_isJoining) return;

    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showMessage('Enter a match code first.');
      return;
    }

    setState(() => _isJoining = true);

    try {
      final matchId = await widget.nakamaService.joinMatchByCode(
        session: widget.nakamaSession,
        code: code,
      );

      if (!mounted) return;
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
      _bubblePlayResult(result);
    } catch (error) {
      debugPrint('Could not join match: $error');
      if (!mounted) return;
      _showMessage('That match code was not found.');
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  void _bubblePlayResult(PlayExitResult? result) {
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Play')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _openQuickMatch,
                icon: const Icon(Icons.bolt),
                label: const Text('Quick Match'),
              ),
              const SizedBox(height: 24),
              const _SectionDivider(label: 'or play a friend'),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isCreating ? null : _createMatch,
                icon: _isCreating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  _isCreating ? 'Creating match...' : 'Create Private Match',
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Match code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isJoining ? null : _joinMatch,
                icon: _isJoining
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _isJoining ? 'Joining match...' : 'Join Private Match',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
