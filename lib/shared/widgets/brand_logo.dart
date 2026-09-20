import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Which of the brand marks to draw.
enum BrandLogoVariant {
  /// The mark with the "Mero swasthya" wordmark under it. For the screens that
  /// introduce the app: the splash, the phone entry, the unlock screen, the
  /// printable card and the PDF header.
  full,

  /// The cross-and-folder mark on its own, in brand colour. For a white or
  /// pale ground — the light app bar, the settings footer, the launcher icon.
  mark,

  /// The same mark as a flat white silhouette, with the doctor and the folder
  /// as cut-outs. For a brand-blue app bar and for Android 13's themed icon.
  markWhite,
}

/// The one place in the app that knows where the brand assets live.
///
/// Screens ask for a variant and a size; they never name a path, so re-cutting
/// the artwork is a change to `tools/brand/make_brand.py` and this file and
/// nothing else.
///
/// [full] is theme-aware. The wordmark's "Mero" is #084E8A, which measures
/// 1.5:1 against the dark scaffold — legible nowhere. On a dark theme the
/// widget reaches for the variant whose type is light and whose mark keeps its
/// own colours.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.variant = BrandLogoVariant.full,
    this.height,
    this.width,
    this.semanticLabel,
  });

  /// The full lock-up, sized by width. The usual call on an intro screen.
  const BrandLogo.full({super.key, this.width, this.height, this.semanticLabel})
      : variant = BrandLogoVariant.full;

  /// The mark alone at [size] square.
  const BrandLogo.mark({super.key, required double size, this.semanticLabel})
      : variant = BrandLogoVariant.mark,
        width = size,
        height = size;

  /// The white mark alone at [size] square, for a brand-blue ground.
  const BrandLogo.markWhite({
    super.key,
    required double size,
    this.semanticLabel,
  })  : variant = BrandLogoVariant.markWhite,
        width = size,
        height = size;

  final BrandLogoVariant variant;
  final double? width;
  final double? height;
  final String? semanticLabel;

  static const String _full = 'assets/brand/logo_full.png';
  static const String _fullDark = 'assets/brand/logo_full_dark.png';
  static const String _mark = 'assets/brand/logo_mark.png';
  static const String _markWhite = 'assets/brand/logo_mark_white.png';

  String _asset(BuildContext context) {
    switch (variant) {
      case BrandLogoVariant.mark:
        return _mark;
      case BrandLogoVariant.markWhite:
        return _markWhite;
      case BrandLogoVariant.full:
        return Theme.of(context).brightness == Brightness.dark
            ? _fullDark
            : _full;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset(context),
      width: width,
      height: height,
      // Never stretched: the mark is a drawn thing, and a squashed cross reads
      // as a mistake rather than as a logo.
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// The mark beside a title, for an app bar.
///
/// Picks the white mark on a brand-coloured bar and the coloured one on a
/// surface-coloured bar, so a screen does not have to know which it has.
class BrandAppBarTitle extends StatelessWidget {
  const BrandAppBarTitle({super.key, required this.child, this.size = 24});

  final Widget child;

  /// 24 rather than 28 by default. The family list's greeting is the account
  /// holder's own name and it has to survive beside the mark: at 28 px, with
  /// the gutter's leading gap, "Namaste, Sita Chaudhary" came back from the
  /// phone as "Namaste, Sita Chaudh...".
  final double size;

  @override
  Widget build(BuildContext context) {
    final bar = Theme.of(context).appBarTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;
    final onBrandBar = ThemeData.estimateBrightnessForColor(bar) ==
        Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        onBrandBar
            ? BrandLogo.markWhite(size: size)
            : BrandLogo.mark(size: size),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: child),
      ],
    );
  }
}
