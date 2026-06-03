import 'package:flutter/material.dart';
import 'generated/design_tokens.g.dart';

// ============================================================================
// Sara (clinician-mobile) — theme tokens
// ============================================================================
//
// PART 13 Layer D3.1 (2026-05-25) — consumes generated tokens from
// `core/generated/design_tokens.g.dart`, emitted from
// `apps/web/src/shared/theme/palettes.ts` by
// `scripts/design-tokens/generate-dart-design-tokens.ts`.
//
// SSoT-aligned tokens (code-generated from web SSoT):
//   - kError / kSuccess / kWarning / kInfo / kNeutral ←→ SEVERITY_COLORS.*
//   - kSafetyActionMinSize ←→ TOUCH_TARGETS.safetyAction (56pt — clinician
//     safety actions: clinical-note sign, AI-draft attest, risk-flag attest,
//     restrictive-intervention end, prescription sign).
//   - SignacareText.body ←→ FONT_SIZES.body (16 px clinician baseline).
//   - The 5 new themes (eucalyptus / warmth / clinicalAaa / therapeutic /
//     crisisSafeDark) parallel the web THEME_PALETTES; same hex values; same
//     intent. Available via `SaraTheme.<id>.theme` for future picker wiring.
//
// Identity (Sara's primary brand):
//   - signacareTheme uses #F0852C ochre primary — the clinician mobile
//     signature, distinct from Viva's purple. Stays default until any future
//     theme-picker change is operator-authorised.

// ---- Identity colours (Sara brand — clinician mobile signature) ----
const Color kPrimary = Color(0xFFF0852C);
const Color kPrimaryDark = Color(0xFFD6741F);
const Color kSurface = Color(0xFFFBF8F5);
const Color kCard = Color(0xFFFFFFFF);
const Color kText = Color(0xFF3D484B);
const Color kTextLight = Color(0xFF6B7E82);
const Color kDivider = Color(0xFFE8E0D8);

// ---- Severity colours (PART 13 Layer A SSoT — mirror of web SEVERITY_COLORS) ----
const Color kSuccess = SignacareDesignTokens.severitySuccess; // Forest green (was #2E7D32; SSoT alignment)
const Color kWarning = SignacareDesignTokens.severityWarning; // Deep amber (was #E65100; SSoT alignment)
const Color kError = SignacareDesignTokens.severityCritical;  // Muted terracotta — REPLACES #B71C1C
                                          // bright red per the alert-fatigue
                                          // principle. Pair with icon + label.
const Color kInfo = SignacareDesignTokens.severityInfo;       // Deep teal (was #327C8D; SSoT alignment)
const Color kNeutral = SignacareDesignTokens.severityNeutral; // Slate (disabled / informational)

// ---- Touch-target SSoT (mirror of TOUCH_TARGETS in web palettes.ts) ----
//
// kSafetyActionMinSize is the 56pt × 56pt hit-box for clinician safety actions
// where mis-tap risk carries clinical harm: clinical-note sign, AI-draft
// attest, risk-flag attest, restrictive-intervention end, prescription sign,
// escalation acknowledge. Apply as:
//   ElevatedButton.styleFrom(minimumSize: kSafetyActionMinSize)
// for buttons that perform safety-critical writes. General buttons use the
// standard 48pt (well above WCAG 2.1 / iOS HIG 44pt floor).
const Size kSafetyActionMinSize = Size(
  SignacareDesignTokens.touchTargetSafetyActionPx,
  SignacareDesignTokens.touchTargetSafetyActionPx,
);

// ---- Clinician font scale (PART 13 Layer A SSoT — FONT_SIZES.body = 16 px) ----
//
// Sara is clinician-facing; we use the standard FONT_SIZES.body (16 px) rather
// than the +2 px patient-app baseline. Below the 16 px text-input floor would
// also trigger iOS auto-zoom; held above on all input controls.
const double _kClinicianHeading = SignacareDesignTokens.fontSizeHeadingPx;   // up from 22 — WCAG large-text guidance
const double _kClinicianTitle = 18.0;     // up from 16
const double _kClinicianBody = SignacareDesignTokens.appBodySizePx;      // up from 14 — clinical body baseline
const double _kClinicianBodySmall = SignacareDesignTokens.fontSizeBodySmallPx; // table cells / secondary
const double _kClinicianCaption = SignacareDesignTokens.fontSizeCaptionPx;   // captions only — timestamps, tags
const double _kClinicianAppBar = 18.0;    // up from 17
const double _kClinicianTabLabel = 14.0;  // up from 13

// Tabular figures feature set for numeric content. Equal-width digits prevent
// row-to-row misread on aligned medication / lab / dose / vitals / score
// columns.
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
  FontFeature.liningFigures(),
];

// ============================================================================
// _buildSaraTheme — structural factory (PART 13 Layer D3.1)
// ============================================================================
//
// Eliminates 6-fold duplication that would otherwise occur when declaring
// 6 ThemeData values (signacare + eucalyptus + warmth + clinicalAaa +
// therapeutic + crisisSafeDark). All themes share the same component themes,
// touch targets, typography scale, and feature-flag-style behaviour — only
// colour-bearing seeds differ. Adding a 7th theme later is a single call,
// not a copy-paste.

ThemeData _buildSaraTheme({
  required Color seed,
  required Brightness brightness,
  required Color scaffoldBg,
  required Color textColor,
  required Color textLightColor,
  required Color dividerColor,
  Color? cardColor,
}) {
  final card = cardColor ?? (brightness == Brightness.dark ? const Color(0xFF1A2025) : Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ),
    fontFamily: 'SF Pro Text',
    scaffoldBackgroundColor: scaffoldBg,
    appBarTheme: AppBarTheme(
      backgroundColor: card,
      foregroundColor: textColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: _kClinicianAppBar,
        color: textColor,
        letterSpacing: -0.3,
        fontFeatures: kTabularFigures,
      ),
      iconTheme: IconThemeData(color: seed),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: seed,
        foregroundColor: Colors.white,
        // 48pt minimum height for general clinician actions (above WCAG 44pt
        // floor). Safety-critical writes MUST override to kSafetyActionMinSize.
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: _kClinicianBody,
          fontFeatures: kTabularFigures,
        ),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: seed, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kError, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelStyle: TextStyle(color: textLightColor, fontSize: 15),
      // 16 px minimum on text inputs prevents iOS auto-zoom-on-focus.
      hintStyle: TextStyle(color: textLightColor, fontSize: _kClinicianBody),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scaffoldBg,
      selectedColor: seed.withAlpha(31), // ≈ 12% opacity
      labelStyle: const TextStyle(
        fontSize: _kClinicianCaption,
        fontWeight: FontWeight.w500,
        fontFeatures: kTabularFigures,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(color: dividerColor, thickness: 1, space: 0),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: card,
      selectedItemColor: seed,
      unselectedItemColor: textLightColor,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: const TextStyle(
        fontSize: _kClinicianCaption,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: _kClinicianCaption),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: seed,
      unselectedLabelColor: textLightColor,
      indicatorColor: seed,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: _kClinicianTabLabel),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: _kClinicianTabLabel),
    ),
  );
}

// ---- The 13-theme catalogue (parity with web THEME_PALETTES) ----
//
// signacareTheme stays the default and is exported as the bare name (back-compat
// with main.dart's `theme: signacareTheme`). The other 5 are exposed via the
// `SaraTheme` enum below for future picker wiring.

final ThemeData signacareTheme = _buildSaraTheme(
  seed: kPrimary,
  brightness: Brightness.light,
  scaffoldBg: kSurface,
  textColor: kText,
  textLightColor: kTextLight,
  dividerColor: kDivider,
  cardColor: kCard,
);

final ThemeData eucalyptusTheme = _buildSaraTheme(
  seed: const Color(0xFF4A6B5C),
  brightness: Brightness.light,
  scaffoldBg: const Color(0xFFF7F5F0),
  textColor: const Color(0xFF1F2D26),
  textLightColor: const Color(0xFF6B7E82),
  dividerColor: const Color(0xFFD8E0DA),
);

final ThemeData warmthTheme = _buildSaraTheme(
  seed: const Color(0xFF8E5A3C),
  brightness: Brightness.light,
  scaffoldBg: const Color(0xFFFCF8F3),
  textColor: const Color(0xFF2E2218),
  textLightColor: const Color(0xFF8B7560),
  dividerColor: const Color(0xFFE6D9C5),
);

final ThemeData clinicalAaaTheme = _buildSaraTheme(
  seed: const Color(0xFF003D7A),
  brightness: Brightness.light,
  scaffoldBg: const Color(0xFFFFFFFF),
  textColor: const Color(0xFF000000),
  textLightColor: const Color(0xFF374151),
  dividerColor: const Color(0xFFD1D5DB),
  cardColor: const Color(0xFFFAFAFA),
);

final ThemeData therapeuticTheme = _buildSaraTheme(
  seed: const Color(0xFF4F6BA5),
  brightness: Brightness.light,
  scaffoldBg: const Color(0xFFF8F9FB),
  textColor: const Color(0xFF1A2238),
  textLightColor: const Color(0xFF6B7280),
  dividerColor: const Color(0xFFE0E4EC),
);

final ThemeData crisisSafeDarkTheme = _buildSaraTheme(
  seed: const Color(0xFF82B8C9),
  brightness: Brightness.dark,
  scaffoldBg: const Color(0xFF0A1419),
  textColor: const Color(0xFFD8E0E5),
  textLightColor: const Color(0xFF8E9BA3),
  dividerColor: const Color(0xFF2D3B45),
  cardColor: const Color(0xFF1A2025),
);

/// Sara theme catalogue — parity with web THEME_PALETTES.
///
/// Active selection mechanism (picker UI) is a future scope; this enum makes
/// the palettes available for that picker to consume. Default in
/// `main.dart` MaterialApp stays `signacareTheme` until a picker is wired.
enum SaraTheme {
  signacare,
  eucalyptus,
  warmth,
  clinicalAaa,
  therapeutic,
  crisisSafeDark;

  ThemeData get theme {
    switch (this) {
      case SaraTheme.signacare:
        return signacareTheme;
      case SaraTheme.eucalyptus:
        return eucalyptusTheme;
      case SaraTheme.warmth:
        return warmthTheme;
      case SaraTheme.clinicalAaa:
        return clinicalAaaTheme;
      case SaraTheme.therapeutic:
        return therapeuticTheme;
      case SaraTheme.crisisSafeDark:
        return crisisSafeDarkTheme;
    }
  }

  String get displayName {
    switch (this) {
      case SaraTheme.signacare:
        return 'SignaCare (default)';
      case SaraTheme.eucalyptus:
        return 'Eucalyptus';
      case SaraTheme.warmth:
        return 'Patient Warmth';
      case SaraTheme.clinicalAaa:
        return 'Clinical AAA';
      case SaraTheme.therapeutic:
        return 'Therapeutic';
      case SaraTheme.crisisSafeDark:
        return 'Crisis-Safe Dark';
    }
  }
}

// Shared text styles — clinician scale with tabular figures on numeric variants.
class SignacareText {
  static const heading = TextStyle(
    fontSize: _kClinicianHeading,
    fontWeight: FontWeight.w700,
    color: kText,
    letterSpacing: -0.5,
    height: 1.2,
    fontFeatures: kTabularFigures,
  );
  static const title = TextStyle(
    fontSize: _kClinicianTitle,
    fontWeight: FontWeight.w600,
    color: kText,
    height: 1.3,
    fontFeatures: kTabularFigures,
  );
  static const body = TextStyle(
    fontSize: _kClinicianBody,
    fontWeight: FontWeight.w400,
    color: kText,
    height: 1.5,
    fontFeatures: kTabularFigures,
  );
  static const bodySmall = TextStyle(
    fontSize: _kClinicianBodySmall,
    fontWeight: FontWeight.w400,
    color: kText,
    height: 1.4,
    fontFeatures: kTabularFigures,
  );
  static const caption = TextStyle(
    fontSize: _kClinicianCaption,
    fontWeight: FontWeight.w400,
    color: kTextLight,
    height: 1.4,
    fontFeatures: kTabularFigures,
  );
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: kTextLight,
    letterSpacing: 0.3,
    fontFeatures: kTabularFigures,
  );

  /// Numeric-emphasis style for clinical data tables (vitals, doses, lab
  /// values, scores). Slight weight bump over body for visual lock against
  /// row-to-row misread. Equivalent of web's `<Typography variant="data">`.
  static const data = TextStyle(
    fontSize: _kClinicianBodySmall,
    fontWeight: FontWeight.w500,
    color: kText,
    height: 1.4,
    fontFeatures: kTabularFigures,
  );
}

// Status chip colours — pair with icon + text label per the alert-fatigue
// principle (never colour alone). 'closed' status uses kError (terracotta);
// previously used the bright #B71C1C panic-red which is now retired.
Color statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'active': return kSuccess;
    case 'inactive': return kTextLight;
    case 'closed': return kError;
    case 'draft': return kWarning;
    case 'signed': return kSuccess;
    default: return kInfo;
  }
}
