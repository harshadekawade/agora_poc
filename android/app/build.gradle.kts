plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter's --target-platform / --split-per-abi only trims Flutter's own
// libraries; plugin AARs (Agora) still ship every ABI (~55 MB each). Match
// them to the ABIs Flutter was asked to build. Empty = no filter (all ABIs).
val flutterPlatformToAbi = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val requestedAbis = (project.findProperty("target-platform") as String?)
    ?.split(",")
    ?.mapNotNull { flutterPlatformToAbi[it.trim()] }
    .orEmpty()

// Agora "full" SDK extensions this POC never calls (Agora's app-size guide
// allows removing unused ones). Kept: segmentation (blur), AI noise
// suppression, clear_vision (beauty), screen_capture, video encoder/decoder.
val unusedAgoraExtensions = listOf(
    "libagora_lip_sync_extension.so",
    "libagora_spatial_audio_extension.so",
    "libagora_face_capture_extension.so",
    "libagora_face_detection_extension.so",
    "libagora_ai_echo_cancellation_extension.so",
    "libagora_audio_beauty_extension.so",
    "libagora_content_inspect_extension.so",
    "libagora_video_quality_analyzer_extension.so",
    "libagora_video_av1_encoder_extension.so",
)

android {
    namespace = "com.qispine.poc.agora_poc"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.qispine.poc.agora_poc"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Set per build type: the Flutter plugin puts all three ABIs on every
    // build type, and build-type filters are merged with defaultConfig's, so
    // only a build-type override narrows them. Skipped for --split-per-abi
    // (AGP rejects abiFilters alongside ABI splits).
    val isSplitPerAbi = project.findProperty("split-per-abi") == "true"
    if (requestedAbis.isNotEmpty() && !isSplitPerAbi) {
        buildTypes.configureEach {
            ndk.abiFilters.clear()
            ndk.abiFilters += requestedAbis
        }
    }

    packaging {
        jniLibs {
            excludes += unusedAgoraExtensions.map { "**/$it" }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
