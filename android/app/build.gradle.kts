import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ──────────────────────────────────────────────────────────────────────────
// Release signing config (S8.2) — reads the upload keystore path and
// passwords from key.properties so secrets never land in git.
//
// key.properties format (do NOT commit; entry in .gitignore):
//
//   storePassword=...
//   keyPassword=...
//   keyAlias=upload
//   storeFile=/absolute/path/to/signacare-sara-upload.jks
//
// Generate the upload keystore with:
//
//   keytool -genkey -v -keystore signacare-sara-upload.jks \
//     -keyalg RSA -keysize 4096 -validity 10000 -alias upload \
//     -dname "CN=Signacare PTY Ltd, O=Signacare, C=AU"
//
// Store the .jks file in your password manager / 1Password vault. The
// Google Play Console "Play App Signing" service holds the actual
// signing key — this keystore only signs the upload artifact, so a
// compromise is recoverable via the key-upgrade process. See
// docs/mobile/sara-clinician/SUBMISSION_CHECKLIST.md §3.
// ──────────────────────────────────────────────────────────────────────────
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.signacare.sara"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.signacare.sara"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Use the release signing config if key.properties exists;
            // fall back to debug keys for developer-local `flutter run
            // --release` convenience. CI builds always have key.properties
            // injected from the GitHub secret.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
