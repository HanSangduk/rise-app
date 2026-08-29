plugins {
    id("com.android.application")
    // Firebase 설정(google-services.json) 처리 — 버전은 settings.gradle.kts에서 관리.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Firebase 콘솔 등록 패키지와 일치해야 한다 (rize-218c1 / ai.stra.rize).
    namespace = "ai.stra.rize"
    // Flutter 3.44 기본값은 36인데 permission_handler_android 14.0.0(= permission_handler
    // 13.0.1이 끌고 오는 버전)이 자기 모듈을 compileSdk 37로 컴파일한다. 프로젝트가 36에
    // 머무르면 Flutter Gradle 플러그인이 "plugin(s) require a higher Android SDK version"
    // 오류를 찍고, 어차피 그 플러그인 모듈 때문에 SDK Platform 37은 받아야 한다.
    // (컴파일 대상만 올라갈 뿐 실행 대상은 targetSdk 36 그대로 — 동작 변화 없음.)
    // 최초 빌드 시 `sdkmanager "platforms;android-37"`가 필요할 수 있다.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ai.stra.rize"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Flutter 3.44 기본 minSdk=24 — Firebase Auth 요구(23 이상) 충족.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 인바디 결과지 OCR 한국어 모델(P20). google_mlkit_text_recognition 플러그인은 이걸
    // **compileOnly**로만 참조한다(플러그인 android/build.gradle:53) — 앱이 직접 implementation
    // 하지 않으면 빌드·테스트는 전부 통과하고 **실기기에서 사진을 고르는 순간**
    // NoClassDefFoundError(KoreanTextRecognizerOptions)로 크래시한다. 실측으로 확인(2026-08-23).
    // 버전은 플러그인 0.17.1이 컴파일한 것과 동일해야 한다.
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}

flutter {
    source = "../.."
}
