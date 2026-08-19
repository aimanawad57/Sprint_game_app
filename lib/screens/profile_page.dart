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
            _StreakCard(profile: loadedProfile),
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
      title: 'Performance',
      children: [
        _WinRateSummary(winRate: profile.winRate),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ProfileMetric(
                  width: width,
                  icon: Icons.sports_esports_rounded,
                  label: 'Games',
                  value: '${profile.gamesPlayed}',
                ),
                _ProfileMetric(
                  width: width,
                  icon: Icons.emoji_events_rounded,
                  label: 'Wins',
                  value: '${profile.wins}',
                ),
                _ProfileMetric(
                  width: width,
                  icon: Icons.close_rounded,
                  label: 'Losses',
                  value: '${profile.losses}',
                ),
                _ProfileMetric(
                  width: width,
                  icon: Icons.timer_outlined,
                  label: 'Best time',
                  value: bestTime,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WinRateSummary extends StatelessWidget {
  const _WinRateSummary({required this.winRate});

  final double winRate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.donut_large_rounded,
            color: colors.onPrimaryContainer,
            size: 36,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Win rate',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${winRate.toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      title: 'Win streaks',
      children: [
        Row(
          children: [
            Expanded(
              child: _StreakMetric(
                icon: Icons.local_fire_department_rounded,
                label: 'Current streak',
                value: profile.currentWinStreak,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StreakMetric(
                icon: Icons.workspace_premium_rounded,
                label: 'Best streak',
                value: profile.bestWinStreak,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StreakMetric extends StatelessWidget {
  const _StreakMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.tertiary, size: 28),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ),
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
