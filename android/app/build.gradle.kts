plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.spicylyrics.spicy_lyrics_engine"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    externalNativeBuild {
        cmake {
            path = file("../../cpp_core/android/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    ndk {
        abiFilters += "arm64-v8a"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.spicylyrics.spicy_lyrics_engine"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("edu.cmu.pocketsphinx:pocketsphinx-android:5prealpha-release")
}
