import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/core/network/dio_client.dart';

part 'center_contact_provider.g.dart';

/// 센터 신원 — 상호·전화·주소(P55 대기실, P56 L10에서 상호까지).
///
/// 출처는 `GET /v1/public/center`(v2.29) 하나다. 어드민 "센터 신원" 폼이 저장하는 그 3칸이
/// 그대로 내려오고, 전화·주소가 비어 있으면 **서버가** 사업자 정보로 폴백해 준다(앱이
/// 합치지 않는다 — 화면마다 다른 번호를 말하는 자기모순을 막기 위해 서버 한 곳에서 한다).
///
/// **왜 `GET /v1/center`가 아니라 공개 엔드포인트인가**: 대기실 사용자는 전화 인증만
/// 끝났고 아직 회원이 아니라 Principal에 센터가 없다. `centerPolicyProvider`는 세션이
/// 없으면 호출을 아예 건너뛴다(401/403 소음 방지). 무인증 경로라 로그인 전·후 어느
/// 화면에서도 같은 provider를 쓸 수 있고, 그래서 홈 헤더·마이 탭의 센터명도 여기서 읽는다.
///
/// **비어 있는 것이 정상 상태다.** 센터 신원은 대표가 어드민에서 채워야 생기고, 오늘
/// 프로덕션은 세 칸이 모두 빈 문자열이다. 그래서 이 provider는 실패를 던지지 않고
/// **빈 값을 돌려준다** — 화면은 전화번호가 있을 때만 통화 버튼을 그리고, 상호는
/// [CenterContact.displayName]이 임시 상수로 채운다. 없는 번호를 지어내지 않고, 못
/// 불러왔다고 사용자를 놀래지도 않는다.
class CenterContact {
  const CenterContact({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.openHour,
    this.closeHour,
  });

  /// 센터 상호 — 서버 값 그대로(미등록이면 빈 문자열). 화면은 [displayName]을 쓴다.
  final String name;
  final String phone;
  final String address;

  /// 수업 시간(계약 v2.34 `open_hour`·`close_hour`) — **첫 슬롯 시작·마지막 슬롯 시작**이라
  /// 끝 시각 표기는 `closeHour + 1`이다([hoursLabel]). 구서버·미설정이면 null이고, 그때 화면은
  /// 행 자체를 그리지 않는다 — 앱이 9·21 기본값을 지어내 "설정한 사실"처럼 찍지 않는다.
  final int? openHour;
  final int? closeHour;

  bool get hasName => name.trim().isNotEmpty;
  bool get hasPhone => phone.trim().isNotEmpty;
  bool get hasAddress => address.trim().isNotEmpty;
  bool get isEmpty => !hasName && !hasPhone && !hasAddress;

  /// 두 칸이 모두 있고 말이 되는 값(0~23, 시작 ≤ 끝)일 때만 — 한쪽만 온 응답은 그리지 않는다.
  bool get hasHours {
    final o = openHour, c = closeHour;
    return o != null && c != null && o >= 0 && c <= 23 && o <= c;
  }

  /// "09:00–22:00" — 마지막 슬롯 시작(21)을 그대로 찍으면 한 시간이 증발한다.
  String get hoursLabel {
    if (!hasHours) return '';
    String two(int h) => h.toString().padLeft(2, '0');
    return '${two(openHour!)}:00–${two(closeHour! + 1)}:00';
  }

  /// 화면에 찍는 상호 — 서버 값이 있으면 그것, 없으면 [AppConfig.centerFullName](임시 표시).
  /// 어드민의 `centerDisplayName`과 같은 규칙·같은 폴백 문자열이다.
  String get displayName => hasName ? name.trim() : AppConfig.centerFullName;
}

/// 재시도하지 않는다 — 이 정보는 화면의 부가물이라 실패가 화면을 막지 않아야 하고,
/// 백오프 타이머가 위젯 테스트에 남는 것도 피한다(P46에서 겪은 자리).
Duration? _noRetry(int retryCount, Object error) => null;

/// [centerId]가 있으면 `?center=`로 **그 센터**를 묻는다(계약 v2.33·v2.34) — 2호점에 요청을
/// 보낸 사람의 대기실이 1호점 전화번호를 찍으면 남의 센터다. `null`(홈 헤더·마이 탭·요청 전
/// 대기실)은 파라미터 없이 종전대로 기본 센터다. family로 두는 이유: 같은 화면이 두 센터를
/// 동시에 볼 일은 없지만, 홈 헤더의 기본 인스턴스가 대기실의 선택에 따라 흔들리면 안 된다.
@Riverpod(retry: _noRetry)
Future<CenterContact> centerContact(Ref ref, String? centerId) async {
  final dio = ref.watch(dioProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>(
      '/v1/public/center',
      queryParameters: centerId == null || centerId.isEmpty ? null : {'center': centerId},
    );
    final data = res.data ?? const <String, dynamic>{};
    return CenterContact(
      name: (data['name'] as String?)?.trim() ?? '',
      phone: (data['phone'] as String?)?.trim() ?? '',
      address: (data['address'] as String?)?.trim() ?? '',
      // 정수만 받는다 — 문자열·실수로 온 값을 억지로 해석하지 않는다(없는 것과 같다).
      openHour: data['open_hour'] is int ? data['open_hour'] as int : null,
      closeHour: data['close_hour'] is int ? data['close_hour'] as int : null,
    );
  } on DioException {
    // 연락처를 못 불러온 것이 이 화면의 실패는 아니다 — 빈 값으로 조용히 접는다.
    return const CenterContact();
  }
}

/// 화면이 찍는 센터 상호 — 로딩 중·실패·미등록이면 [AppConfig.centerFullName].
///
/// 동기 `String`으로 내려서 헤더·카드가 `AsyncValue` 분기 없이 `ref.watch` 한 줄로 쓴다.
/// 로딩 중에도 임시 상수를 바로 보여주는 것이 의도다 — 상호 한 줄 때문에 홈 헤더가
/// 스피너를 돌릴 이유가 없고, 서버 값이 오면 그 자리에서 바뀐다.
@riverpod
String centerDisplayName(Ref ref) =>
    ref.watch(centerContactProvider(null)).value?.displayName ?? AppConfig.centerFullName;
