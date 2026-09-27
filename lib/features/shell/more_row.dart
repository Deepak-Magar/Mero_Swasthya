import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';

/// One labelled row in a More tab.
///
/// The shape that replaces every unlabeled `⋮` in the app: a glyph, the
/// feature's name in words, an optional line saying what it is for, and a
/// chevron. The audit's first three findings were all features hidden behind a
/// three-dot icon; this is where they went instead.
class MoreRow extends StatelessWidget {
  const MoreRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.body,
    this.trailing,
  });

  final IconData icon;
  final String label;

  /// One line saying what the feature does. Optional, but worth writing for
  /// anything a first-time user would not recognise from its name alone.
  final String? body;

  final VoidCallback onTap;

  /// Replaces the chevron — a count, a state pill.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = AppColors.textSecondaryOf(context);

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      onTap: onTap,
      semanticLabel: label,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.brandTintOf(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, size: 21, color: AppColors.brandOf(context)),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    body!,
                    style: text.bodySmall?.copyWith(color: secondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing ??
              Icon(Icons.chevron_right_rounded, color: secondary),
        ],
      ),
    );
  }
}
