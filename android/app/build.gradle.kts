import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (never committed; CI writes it from
// GitHub Secrets). Without it, release builds are DEBUG-SIGNED and not for stores.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "ma.sahbi.sahbi"
    // permission_handler_android 13.x compiles against SDK 37 (build warning on 36).
    // compileSdk is backward compatible; targetSdk stays at the Flutter default.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ma.sahbi.sahbi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // SAHBI: Android 8.0+ (spec). Needed for notification channels, AudioFocusRequest.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        // CI builds: 3000 + run number, the SAME for the universal and the
        // arm64 APK (gradle.properties sets force-version-code-ignoring-abi).
        // Before, the arm64 APK got 2000 + run and the universal only the run
        // number, so installing the universal over an arm64 build was a
        // "downgrade" and Android said "App not installed". 3000+ is above
        // every APK published so far (max 2028), so any old install updates.
        versionCode = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull()?.plus(3000) ?: flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Fixed key for debug and sideloaded (no-secrets) builds. Every CI
        // runner used to create a new random debug key, so each new APK had a
        // different signature and Android refused to install it over the old
        // one ("conflicts with an existing package"). This key is public on
        // purpose (password "android", like Android's own debug key): it only
        // keeps phone updates working and must never be used for a store.
        getByName("debug") {
            storeFile = file("sahbi-sideload.keystore")
            storePassword = "android"
            keyAlias = "sahbi"
            keyPassword = "android"
        }
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Lets `flutter build apk --release` work without secrets. NOT for stores.
                signingConfigs.getByName("debug")
            }
            // Keeps Vosk/JNA (looked up by name from native code) under R8.
            proguardFiles("proguard-rules.pro")
        }
    }
}

dependencies {
    // Offline "MIMO" wake word (Apache-2.0). @aar: JNA must come as its
    // Android AAR (native libjnidispatch), not the desktop JAR.
    implementation("com.alphacephei:vosk-android:0.3.75@aar")
    implementation("net.java.dev.jna:jna:5.18.1@aar")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
