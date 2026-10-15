// 순수 도메인 — 체형 사진 Storage 경로 규칙. Flutter/Firebase 의존 0, codegen 0.

import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';

/// 체형 사진(P8 민감정보)이 Firebase Storage에 놓이는 자리.
///
/// ```
/// members/{memberId}/body/{yyyyMMdd}-{pose}-{direction}-{epochMillis}.jpg
/// ```
///
/// **이 형태는 앱이 고른 게 아니라 이미 배포된 보안 규칙이 정한 것이다**
/// (`ptdesk/storage.rules`):
///
/// ```
/// match /members/{memberId}/body/{fileName} {
///   allow create, update: if isSignedIn()
///     && myMemberId() == memberId          // Firestore users/{uid}.member_id
///     && hasSensitiveConsent(memberId)
///     && isImageUnder10MB();               // size < 10MB && contentType ∈ image/(jpeg|png|webp)
/// }
/// ```
///
/// 여기서 파생되는 제약이 셋이고, 하나라도 어기면 업로드가 403으로 조용히 막힌다:
///
/// 1. **세그먼트가 정확히 4개**(`members` / memberId / `body` / fileName)여야 한다.
///    날짜를 폴더로 파면 `{fileName}` 와일드카드가 매칭에 실패한다 — 그래서 날짜는
///    폴더가 아니라 **파일명 앞머리**에 붙인다(이름순 정렬 = 시간순이라는 이득도 있다).
/// 2. 경로 키는 **memberId**다. uid가 아니다 — 규칙이 uid를 Firestore에서
///    member_id로 옮겨 심고 그 값과 경로를 대조한다.
/// 3. contentType은 `image/jpeg`·`image/png`·`image/webp` 중 하나(P74 — 종전 `image/*`에는
///    `image/svg+xml`처럼 스크립트를 품는 형식이 들어갔다), 크기는 10MB 미만([maxUploadBytes]).
///    업로더는 `image/jpeg`를 **명시**한다(body_photo_uploader.dart).
///
/// 파일명 끝의 epochMillis는 같은 날 같은 포즈를 다시 찍었을 때 앞 사진을 덮지
/// 않기 위한 것이다. 반대로 **업로드 재시도는 같은 경로를 재사용해야** 실패한
/// 조각이 버킷에 유령으로 쌓이지 않는다 — 그래서 경로는 촬영 시점에 한 번 만들고
/// 재시도는 그 값을 다시 쓴다(CameraViewModel.pendingRetry).
abstract final class BodyPhotoStoragePath {
  static const rootPrefix = 'members';
  static const folder = 'body';

  /// storage.rules의 `isImageUnder10MB()`와 같은 값. 넘으면 규칙이 403으로 막으므로
  /// 클라이언트가 먼저 걸러 사용자에게 이유를 말해준다.
  static const maxUploadBytes = 10 * 1024 * 1024;

  static String build({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime capturedAt,
  }) {
    final day = _yyyymmdd(capturedAt);
    final stamp = capturedAt.millisecondsSinceEpoch;
    return '$rootPrefix/${_segment(memberId)}/$folder/'
        '$day-${_segment(pose)}-${direction.wireValue}-$stamp.jpg';
  }

  static String _yyyymmdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  /// memberId는 서버에서 온 값이지만 경로 조각으로 쓰기 전에 정규화한다.
  /// `/`나 `..`가 섞여 들어오면 세그먼트 수가 달라져 규칙 매칭이 통째로 빗나가고
  /// (= 전면 차단 규칙에 걸려 403), 최악의 경우 다른 회원 prefix를 가리킨다.
  /// 허용: 영숫자 · `-` · `_`.
  static String _segment(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }
}
