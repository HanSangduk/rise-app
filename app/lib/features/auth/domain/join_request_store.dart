import 'dart:convert';

import 'package:rise_member/core/utils/phone_format.dart';

/// 로컬에 남겨 두는 가입 요청 흔적 — 앱을 껐다 켜도 "승인 대기 중"으로 복귀시킨다.
///
/// [phone]은 항상 E.164 정규화 형태로 보관한다. 승인 대기는 **그 번호의 상태**이지
/// 기기의 상태가 아니므로, 번호를 바꿔 다시 로그인했을 때 남의 대기 카드가
/// 잘못 뜨지 않으려면 복원 시점에 번호를 반드시 대조해야 한다([matches]).
class JoinRequestRecord {
  const JoinRequestRecord({
    required this.phone,
    required this.requestedAt,
    this.centerId = '',
  });

  /// E.164 정규화된 요청 번호(+8210...).
  final String phone;

  /// 요청 성공 시각 — "다시 요청" 30초 쿨다운의 기준점.
  final DateTime requestedAt;

  /// 요청을 보낸 센터(계약 v2.33에서 회원이 고른 값). **구버전 기록(v1 JSON)에는 없다** → ''.
  /// 서버가 `join_request.center_id`(v2.34)를 주기 전·못 줄 때의 폴백 — 대기실이 어느 센터의
  /// 연락처를 보여줄지 정한다. 빈 값이면 기본 센터(종전 동작).
  final String centerId;

  /// 저장된 요청이 [otherPhone]의 것인지. 표기가 달라도(하이픈/국가코드)
  /// 정규화 후 비교하므로 "010-1234-5678"과 "+821012345678"은 같게 본다.
  bool matches(String otherPhone) => phone == normalizeKoreanPhone(otherPhone);

  String encode() => jsonEncode({
        'phone': phone,
        'requested_at': requestedAt.toIso8601String(),
        'center_id': centerId,
      });

  /// 손상·구버전 문자열은 조용히 null — 저장소 한 줄 때문에 로그인이 막히면 안 된다.
  static JoinRequestRecord? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final phone = map['phone'];
      final requestedAt = DateTime.tryParse(map['requested_at']?.toString() ?? '');
      if (phone is! String || phone.isEmpty || requestedAt == null) return null;
      // center_id는 v2 필드 — 없거나 문자열이 아니면 ''(구 JSON 하위호환, 기록 자체는 유효).
      final centerId = map['center_id'];
      return JoinRequestRecord(
        phone: phone,
        requestedAt: requestedAt,
        centerId: centerId is String ? centerId : '',
      );
    } on FormatException {
      return null;
    }
  }
}

/// 도메인 인터페이스 — 구현은 data/join_request_store_impl.dart.
/// 저장은 한 건만 유지한다(마지막 요청). 연결이 끝나면 [clear].
abstract interface class JoinRequestStore {
  Future<JoinRequestRecord?> read();
  Future<void> save(JoinRequestRecord record);
  Future<void> clear();
}
