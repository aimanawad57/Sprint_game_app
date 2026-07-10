import 'package:flutter/material.dart';

class DisconnectedMatchBanner extends StatelessWidget {
  const DisconnectedMatchBanner({
    super.key,
    required this.onReconnect,
    required this.onAbandon,
    required this.isAbandoning,
  });

  final VoidCallback onReconnect;
  final VoidCallback? onAbandon;
  final bool isAbandoning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'You were disconnected from the match',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onReconnect,
                    child: const Text('Reconnect'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: onAbandon,
                    child: isAbandoning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Abandon'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
