import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase 프로젝트 rize-218c1 설정 — flutterfire CLI 산출물과 동일한 형태를
/// 수기로 유지한다(값 출처: android/app/google-services.json,
/// ios/Runner/GoogleService-Info.plist). 콘솔에서 앱을 재등록하면 이 파일도 갱신.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAQawLECjeyQ3ZQj__YgMWb8WjRf8CI0wg',
    appId: '1:773077624928:android:6e8fdbacda6ef84db0fb05',
    messagingSenderId: '773077624928',
    projectId: 'rize-218c1',
    storageBucket: 'rize-218c1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDbFInJ75AzMFcMjDee6Gn1R9UqM-yXyMw',
    appId: '1:773077624928:ios:b700434a369d2acfb0fb05',
    messagingSenderId: '773077624928',
    projectId: 'rize-218c1',
    storageBucket: 'rize-218c1.firebasestorage.app',
    iosBundleId: 'ai.stra.rize',
  );
}
