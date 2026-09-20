import 'package:flutter/material.dart';

/// The single source of truth for colour in the app.
///
/// Nothing outside this file names a colour. Every screen, chip, banner and
/// card reaches for a token here, so a palette change is one edit rather than
/// forty, and so the clinical colours cannot quietly drift apart from the
/// decorative ones.
///
/// Two families live here and they are not interchangeable:
///
///  * **Brand and neutrals** — [brandBlue], [brandGreen], [background],
///    [surface], [textPrimary], [textSecondary]. These carry the calm. They may
///    be restyled freely.
///  * **Semantic clinical colours** — [triageGreen], [triageAmber], [triageRed],
///    [allergyRed]. These are *safety* colours: they are the difference between
///    "come back in a month" and "go to hospital tonight". They stay distinct,
///    they stay high-contrast, and they are never reused for decoration.
class AppColors {
  const AppColors._();

  // --- Brand -------------------------------------------------------------

  /// Primary CTA, active states, app-bar accents.
  static const Color brandBlue = Color(0xFF004C8A);

  /// Success, synced, "live" indicators, secondary accents.
  static const Color brandGreen = Color(0xFF109B75);

  // --- Neutrals ----------------------------------------------------------

  /// Scaffold background. Never white — the cards are white, and a card only
  /// reads as a card if the page behind it is not.
  static const Color background = Color(0xFFF8FAFC);

  /// Cards and sheets.
  static const Color surface = Color(0xFFFFFFFF);

  /// Headings and body. Never pure black: #000 on white vibrates, and at the
  /// brightness a phone runs at outdoors it reads as harsher, not clearer.
  static const Color textPrimary = Color(0xFF1E293B);

  /// Timestamps, subtext, inactive icons.
  static const Color textSecondary = Color(0xFF64748B);

  // --- Semantic clinical colours -----------------------------------------
  //
  // Spec §16: colour is never the only carrier. Each of these always ships
  // with an icon and a word.

  static const Color triageGreen = Color(0xFF109B75);
  static const Color triageAmber = Color(0xFFD97706);
  static const Color triageRed = Color(0xFFDC2626);

  /// The allergy chip on S08 and S21. Same red as [triageRed] by design — an
  /// allergy and a red triage are the same order of "stop and read this".
  static const Color allergyRed = Color(0xFFDC2626);

  /// The allergy chip's ground.
  static const Color allergyTint = Color(0xFFFEF2F2);

  // --- Tints -------------------------------------------------------------
  //
  // Opaque rather than alpha-blended: these sit on top of cards *and* on top
  // of the page, and a translucent tint that changes shade depending on what
  // is behind it is not a safety colour any more.

  static const Color triageGreenTint = Color(0xFFECFDF5);
  static const Color triageAmberTint = Color(0xFFFFFBEB);
  static const Color triageRedTint = Color(0xFFFEF2F2);

  /// The quiet ground under a brand-blue tile or a selected row.
  static const Color brandBlueTint = Color(0xFFE8F0F8);

  // --- Dark mode -----------------------------------------------------------
  //
  // The brand and semantic colours above are chosen against white. Measured on
  // the phone against the dark scaffold (#0F172A), `brandBlue` comes out at
  // **2.04:1** — invisible. Dark mode therefore keeps the *hues* and lifts the
  // lightness; it does not invent new colours, and it does not reuse the light
  // ones and hope.
  //
  // Ratios against the dark scaffold / dark surface (#1E293B):
  //   brandBlueDark   8.01 / 6.57      triageRedDark    6.45 / 5.29
  //   brandGreenDark  9.18 / 7.52      triageAmberDark 10.69 / 8.76

  static const Color brandBlueDark = Color(0xFF7FB3E0);
  static const Color brandGreenDark = Color(0xFF4ECFA6);
  static const Color triageRedDark = Color(0xFFF87171);
  static const Color triageAmberDark = Color(0xFFFBBF24);
  static const Color triageGreenDark = Color(0xFF4ECFA6);

  /// The tinted ground under a tile or chip on a dark surface.
  static const Color brandBlueTintDark = Color(0xFF16304A);

  /// Anything drawn on top of [brandBlueDark], which is a *light* fill in dark
  /// mode and therefore needs dark ink.
  static const Color onBrandDark = Color(0xFF0F172A);

  /// Resolves the brand colour for [brightness].
  ///
  /// Widgets that paint brand blue directly — a tile foreground, a keypad
  /// digit, a PIN dot — go through here rather than naming [brandBlue], so a
  /// dark phone does not get dark-on-dark.
  static Color brand(Brightness brightness) =>
      brightness == Brightness.dark ? brandBlueDark : brandBlue;

  /// Resolves the tinted ground for [brightness].
  static Color brandTint(Brightness brightness) =>
      brightness == Brightness.dark ? brandBlueTintDark : brandBlueTint;

  /// [brand] and [brandTint] for the theme in scope.
  ///
  /// These are what widgets call. Naming [brandBlue] directly inside a widget
  /// is what produced 2.04:1 text on a dark phone, so the constant stays for
  /// the theme and the palette, and screens go through these.
  static Color brandOf(BuildContext context) =>
      brand(Theme.of(context).brightness);

  static Color brandTintOf(BuildContext context) =>
      brandTint(Theme.of(context).brightness);

  /// Ink for content drawn on top of [brandOf].
  static Color onBrandOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? onBrandDark : onBrand;

  /// Danger ink on a *themed* surface — an allergy line, a failed sync row,
  /// an overdue contact — for the theme in scope.
  ///
  /// [onTriageRed] is the dark red meant for a *pale* red tint. Drawn straight
  /// onto the dark card it measured 1.76:1 on the provider's recent-patient
  /// list (measured off a screenshot on the Nothing A063) — on the one line
  /// that says which drug would kill the patient. On a dark ground the signal
  /// has to be the light red instead.
  static Color dangerInkOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? triageRedDark
          : onTriageRed;

  /// The "this is done / this is fine" ink on a *themed* surface.
  ///
  /// Brand green measures 4.16:1 on the dark card — under the 4.5:1 a status
  /// label needs — so dark mode uses the lifted green, the same one the theme
  /// already gives [ColorScheme.secondary].
  static Color successInkOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? brandGreenDark
          : brandGreen;

  /// Quiet ink on a *themed* surface — a card, the scaffold — for the theme
  /// in scope.
  ///
  /// [textSecondary] is slate-500, which measures 4.76:1 on white and 3.07:1
  /// on the dark card (measured off a screenshot of S06 on the Nothing A063).
  /// No single grey can clear 4.5:1 against both grounds, so anything drawn on
  /// a surface that follows the theme has to resolve at build time. Content on
  /// a ground that stays light in both modes — a triage tint, the sync chip's
  /// grey pill, the printable card — keeps naming [textSecondary] directly.
  static Color textSecondaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  /// The demo-OTP banner and the "activated" success state (S02, S18).
  static const Color brandGreenTint = Color(0xFFECFDF5);

  // --- Ink on a tint -----------------------------------------------------
  //
  // The semantic colours above are the *signal*: icon, border, dot, fill, and
  // short bold labels. Multi-line body copy sitting on a tint uses the ink
  // below instead — same hue, materially more contrast.
  //
  // #DC2626 on #FEF2F2 measures 4.41:1, which clears AA for large and bold
  // text and for graphical objects but sits just under the 4.5:1 body
  // threshold. The reasons under a red triage banner are the most consequential
  // sentences in the app, so they get 7.60:1 rather than 4.41:1.

  static const Color onTriageGreen = Color(0xFF065F46);
  static const Color onTriageAmber = Color(0xFF92400E);
  static const Color onTriageRed = Color(0xFF991B1B);

  // --- Structural --------------------------------------------------------

  /// Anything drawn on top of [brandBlue] or a photographic surface.
  static const Color onBrand = Color(0xFFFFFFFF);

  /// The ground a QR code is painted on. Not a style choice — a scanner needs
  /// black on white, so this one is white because physics says so.
  static const Color qrCanvas = Color(0xFFFFFFFF);

  /// The scrim over a live camera preview (S20) and over a full-screen image
  /// (S10 detail). Black because it is darkening a photograph.
  static const Color cameraBackdrop = Color(0xFF000000);

  // --- Print ---------------------------------------------------------------
  //
  // A.7's printed card is a *picture of a piece of paper*. It is captured and
  // shared as an image, so it must come out identical whether the phone is in
  // dark mode or not — these deliberately do not follow the theme. They are
  // tokens all the same, so that "the print palette" is a thing with a name
  // rather than five literals buried in a widget.

  /// Near-black ink on the printed card. Darker than [textPrimary] because
  /// paper and a cheap printer both eat contrast.
  static const Color printInk = Color(0xFF14181F);

  /// Secondary text on the printed card.
  static const Color printMuted = Color(0xFF5A6472);

  /// The card's own border, so its edge survives being photocopied.
  static const Color printBorder = Color(0xFFD5DAE2);

  /// The "ask for the PIN" notice on the card.
  static const Color printNoticeBg = Color(0xFFFFF4E0);
  static const Color printNoticeBorder = Color(0xFFE8B457);

  /// The drop shadow behind a map marker, so a dark pin stays visible over
  /// dark terrain.
  static Color get markerShadow => Colors.black.withValues(alpha: 0.54);

  /// The shadow under a [surface] card. One shadow, everywhere.
  static Color get cardShadow => Colors.black.withValues(alpha: 0.05);

  /// A hairline used only where a shape genuinely needs an edge — a viewfinder,
  /// a selected toggle. Never as a list divider.
  static Color get hairline => textSecondary.withValues(alpha: 0.18);

  /// The disabled / skeleton grey.
  static Color get skeleton => textSecondary.withValues(alpha: 0.12);
}

/// Triage colours as used by banners, dots and chips.
///
/// Kept as its own class because the rest of the app talks in wire strings
/// (`'red'`, `'amber'`, `'green'`) that come back from the rules engine, and
/// this is where that string becomes a colour, a tint and an icon.
///
/// Spec §16: these are always paired with an icon and text, never colour alone.
class TriageColors {
  const TriageColors._();

  static const Color green = AppColors.triageGreen;
  static const Color amber = AppColors.triageAmber;
  static const Color red = AppColors.triageRed;

  static const Color greenBg = AppColors.triageGreenTint;
  static const Color amberBg = AppColors.triageAmberTint;
  static const Color redBg = AppColors.triageRedTint;

  /// The signal colour: icon, border, dot, fill, short bold label.
  static Color fg(String? level) => switch (level) {
        'red' => red,
        'amber' => amber,
        'green' => green,
        _ => AppColors.textSecondary,
      };

  /// The tint a [fg] of the same level sits on.
  static Color bg(String? level) => switch (level) {
        'red' => redBg,
        'amber' => amberBg,
        'green' => greenBg,
        _ => AppColors.background,
      };

  /// Body copy on a [bg] of the same level. Darker than [fg] so that a
  /// multi-line reason clears 4.5:1 rather than 4.41:1.
  static Color ink(String? level) => switch (level) {
        'red' => AppColors.onTriageRed,
        'amber' => AppColors.onTriageAmber,
        'green' => AppColors.onTriageGreen,
        _ => AppColors.textPrimary,
      };

  /// Spec §16: colour AND icon AND text. Filled glyphs, because inside a
  /// triage banner weight is the point — this is the one place the app is
  /// allowed to shout.
  static IconData icon(String? level) => switch (level) {
        'red' => Icons.error,
        'amber' => Icons.warning_amber_rounded,
        'green' => Icons.check_circle,
        _ => Icons.help_outline,
      };
}
