import 'package:flutter/foundation.dart';

/// API 서버 설정. Base `/v1` (API계약_v1.md).
///
/// 로컬 백엔드 기본값 — 실제 배포 시 `--dart-define=API_BASE_URL=https://...`
/// 로 오버라이드(TODO: CI/CD에서 환경별 주입).
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// 릴리스 빌드가 로컬 주소를 들고 나가지 못하게 한다.
  ///
  /// **조용히 틀리는 종류다.** `--dart-define`을 빠뜨린 릴리스 APK는 빌드도 되고
  /// 설치도 되고 실행도 되는데, 모든 요청이 `localhost:8080`으로 가서 **전부**
  /// 실패한다. 그 화면은 "연결이 불안정해요"라 회원도 대표도 원인을 못 찾는다.
  /// CI나 스크립트로 강제하는 자리가 지금 없으므로 앱이 스스로 막는다.
  ///
  /// 디버그·테스트에서는 로컬 백엔드가 정상 사용이라 검사하지 않는다.
  static void assertConfiguredForRelease() {
    if (!kReleaseMode) return;
    final local = baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1');
    if (local) {
      throw StateError(
        'API_BASE_URL이 설정되지 않았습니다 — 릴리스 빌드는 '
        '--dart-define=API_BASE_URL=https://... 로 빌드해야 합니다. '
        '(현재: $baseUrl)',
      );
    }
  }

  static const connectTimeoutMs = 10000;
  static const receiveTimeoutMs = 10000;

  /// 데스크 셀프체크인 QR 토큰의 **dev 폴백** — 백엔드 config.go의 CHECKIN_QR_TOKEN
  /// 기본값과 동일.
  ///
  /// 실사용 값은 QrScanScreen이 카메라로 읽은 원문이고(1순위), 이 상수는 스캔 값이
  /// 비었을 때만 쓰인다(HomeRemoteDataSource.selfCheckIn). 카메라가 없는 에뮬레이터·
  /// CI에서 체크인 흐름을 끝까지 돌려보기 위한 통로라 지우지 않는다.
  static const checkinQrToken = String.fromEnvironment(
    'CHECKIN_QR_TOKEN',
    defaultValue: 'rise-desk-checkin',
  );
}
