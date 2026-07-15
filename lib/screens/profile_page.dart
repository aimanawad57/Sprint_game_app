import 'package:flutter/material.dart';

import '../models/player_profile.dart';
import '../utils/elapsed_time_format.dart';
import '../widgets/profile_status_panel.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.displayName,
    required this.email,
    required this.profile,
    required this.profileStatus,
  });

  final String displayName;
  final String email;
  final PlayerProfile? profile;
  final ProfileStatus profileStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _ProfileHeader(displayName: displayName, email: email),
            const SizedBox(height: 24),
            _buildProfileBody(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (profileStatus) {
      case ProfileStatus.loading:
        return ProfileStatusPanel(
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
        final loadedProfile = profile;
        if (loadedProfile == null) {
          return _buildProfileErrorPanel(colorScheme);
        }

        return Column(
          children: [
            _StatsCard(profile: loadedProfile),
            const SizedBox(height: 16),
            _DetailsCard(joinedDate: _formatDate(loadedProfile.createdAt)),
          ],
        );
    }
  }

  Widget _buildProfileErrorPanel(ColorScheme colorScheme) {
    return ProfileStatusPanel(
      leading: const Icon(Icons.error, size: 20),
      label: 'Could not load profile',
      foregroundColor: colorScheme.onErrorContainer,
      borderColor: colorScheme.errorContainer,
      backgroundColor: colorScheme.errorContainer,
    );
  }

  String _formatDate(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '-';

    final localDate = date.toLocal();
    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');
    return '${localDate.year}-$month-$day';
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.displayName, required this.email});

  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        CircleAvatar(
          radius: 42,
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(
            Icons.person,
            size: 44,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(displayName, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          email,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final bestTime = profile.bestTimeMs == null
        ? '-'
        : formatElapsedTimeMs(profile.bestTimeMs!);

    return _ProfileCard(
      title: 'Stats',
      children: [
        _ProfileInfoRow(label: 'Games played', value: '${profile.gamesPlayed}'),
        _ProfileInfoRow(label: 'Wins', value: '${profile.wins}'),
        _ProfileInfoRow(label: 'Losses', value: '${profile.losses}'),
        _ProfileInfoRow(label: 'Best time', value: bestTime),
      ],
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.joinedDate});

  final String joinedDate;

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      title: 'Details',
      children: [_ProfileInfoRow(label: 'Joined', value: joinedDate)],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
