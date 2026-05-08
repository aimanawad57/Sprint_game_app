import 'package:flutter/material.dart';

class BackendStatusPanel extends StatelessWidget {
  const BackendStatusPanel({
    super.key,
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
