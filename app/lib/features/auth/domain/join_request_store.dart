import 'dart:convert';

import 'package:rise_member/core/utils/phone_format.dart';

/// 로컬에 남겨 두는 가입 요청 흔적 — 앱을 껐다 켜도 "승인 대기 중"으로 복귀시킨다.
///
/// [phone]은 항상 E.164 정규화 형태로 보관한다. 승인 대기는 **그 번호의 상태**이지
/// 기기의 상태가 아니므로, 다른 번호로 다시 로그인했을 때 남의 대기 카드가
/// 잘못 뜨지 않으려면 복원 시점에 번호를 반드시 대조해야 한다([matches]).
class JoinRequestRecord {
  const JoinRequestRecord({required this.phone, required this.requestedAt});

  /// E.164 정규화된 요청 번호(+8210...).
  final String phone;

  /// 요청 성공 시각 — "다시 요청" 30초 쿨다운의 기준점.
  final DateTime requestedAt;

  /// 저장된 요청이 [otherPhone]의 것인지. 표기가 달라도(하이픈/국가코드)
  /// 정규화 후 비교하므로 "010-1234-5678"과 "+821012345678"은 같게 본다.
  bool matches(String otherPhone) => phone == normalizeKoreanPhone(otherPhone);

  String encode() => jsonEncode({
        'phone': phone,
        'requested_at': requestedAt.toIso8601String(),
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
      return JoinRequestRecord(phone: phone, requestedAt: requestedAt);
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
