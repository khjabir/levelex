import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Small uppercase label used to title groups of content.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4, left: 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
