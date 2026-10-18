plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.media_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Vendored AndroidX Media3 FFmpeg decoder bindings (Apache-2.0). They must
    // keep their original `androidx.media3.decoder.ffmpeg` package because
    // media3's DefaultRenderersFactory loads the renderer by reflection, so they
    // are kept in a separate source directory rather than inside the app's own
    // tree. The native library they call ships in
    // src/main/jniLibs/arm64-v8a/libffmpegJNI.so — see THIRD_PARTY_NOTICES.md
    // for the FFmpeg build (LGPL) and why it is bundled.
    sourceSets {
        getByName("main") {
            java.srcDir("src/main/media3ffmpeg")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.medio.community"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "Medio Community")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Minification is what makes the keep rule in proguard-rules.pro
            // necessary (its JNI-resolved member is otherwise stripped), so it
            // is stated explicitly instead of relying on Flutter's default.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    val media3 = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-ui:$media3")
}
