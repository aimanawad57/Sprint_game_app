import 'package:flutter/material.dart';

class ProfileStatusPanel extends StatelessWidget {
  const ProfileStatusPanel({
    super.key,
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
