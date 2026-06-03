# Sara (clinician mobile) — R8 / ProGuard rules (S8.2).
#
# Enabled by isMinifyEnabled + isShrinkResources in build.gradle.kts
# release buildType. Strips dead code, obfuscates class/method names,
# and removes unused resources so the release APK is ~40% smaller.
#
# Keep rules below preserve every class that is loaded reflectively —
# R8 cannot trace reflection and will otherwise strip classes that are
# still reachable at runtime, producing NoClassDefFoundError on launch.

# ── Flutter / Dart ──────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── Kotlin ──────────────────────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ── Dio HTTP client (JSON reflection) ───────────────────────────────────
-keep class com.signacare.sara.** { *; }

# ── Riverpod + flutter_secure_storage ───────────────────────────────────
# Secure storage uses reflection to bind to the Android Keystore.
-keep class androidx.security.crypto.** { *; }

# ── Sentry crash reporter (if enabled) ─────────────────────────────────
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# ── Play Core (dynamic features — not used but pulled in transitively) ─
-dontwarn com.google.android.play.core.**
