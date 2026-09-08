import 'package:flutter/foundation.dart';

/// API 서버 설정. Base `/v1` (API계약_v1.md).
///
/// **기본값이 빌드 모드로 갈린다**(P46):
///   · 디버그(`flutter run`·테스트) → 로컬 백엔드. 개발자가 매번 `--dart-define`을
///     붙이지 않아도 되고, 로컬 서버를 띄워 놓고 바로 개발한다.
///   · 릴리스·프로파일 → **프로덕션 Cloud Run**. 종전엔 릴리스도 기본값이
///     `localhost`라 `--dart-define`을 빠뜨린 빌드가 조용히 전멸했다(그 화면은
///     "연결이 불안정해요"라 회원도 대표도 원인을 못 찾는다 — 실제로 실기기
///     테스트에서 이 증상이 났다).
///
/// `--dart-define=API_BASE_URL=...`을 주면 **모드와 무관하게** 그 값이 이긴다
/// (스테이징·에뮬레이터 `10.0.2.2`·실기기에서 로컬 서버 붙이기 등).
abstract final class ApiConfig {
  /// 프로덕션 백엔드(Cloud Run, asia-northeast3). 어드민 Hosting의 `/api` 리라이트가
  /// 가리키는 것과 같은 서비스다.
  static const productionBaseUrl =
      'https://rize-api-773077624928.asia-northeast3.run.app';

  /// 로컬 개발 기본값. 에뮬레이터에서는 호스트가 `10.0.2.2`라 dart-define이 필요하다.
  static const localBaseUrl = 'http://localhost:8080';

  /// 빌드 시 주입된 값(없으면 빈 문자열).
  static const _override = String.fromEnvironment('API_BASE_URL');

  /// 실제로 쓰이는 주소. const가 아닌 이유는 [kDebugMode] 분기 때문이고,
  /// 앱 수명 동안 바뀌지 않는다(dio 생성 시 한 번 읽는다).
  static final String baseUrl = _override.isNotEmpty
      ? _override
      : (kDebugMode ? localBaseUrl : productionBaseUrl);

  /// 릴리스 빌드가 로컬 주소를 들고 나가지 못하게 한다.
  ///
  /// 기본값이 모드별로 갈린 뒤에도 이 가드는 남는다 — 이제 막는 대상이 "빠뜨린
  /// dart-define"이 아니라 **잘못 넣은 dart-define**이다(에뮬레이터용
  /// `10.0.2.2`나 로컬 주소를 그대로 둔 채 스토어 빌드를 뽑는 실수).
  static void assertConfiguredForRelease() {
    if (!kReleaseMode) return;
    final local = baseUrl.contains('localhost') ||
        baseUrl.contains('127.0.0.1') ||
        baseUrl.contains('10.0.2.2');
    if (local) {
      throw StateError(
        '릴리스 빌드가 로컬 주소를 가리키고 있습니다 — '
        '--dart-define=API_BASE_URL 을 빼거나(기본값이 프로덕션입니다) '
        'https 주소로 지정해주세요. (현재: $baseUrl)',
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
