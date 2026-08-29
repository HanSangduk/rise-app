import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/join_dto.dart';

// 계약 v2.2 — GET /v1/me가 표시용 `name`을 주기 시작했다.
//
// 이 필드의 성질이 파싱 규약을 정한다: 서버는 이름을 **best-effort**로만 채운다
// (조회에 실패해도 /v1/me는 성공한다). 미연결 계정이면 omitempty로 키가 아예
// 빠지고, 구버전 서버는 이 키를 모른다. 즉 "없음"이 정상 응답이라,
// 파싱이 여기서 터지면 앱은 부트스트랩 자체를 못 한다(온보딩 진입 불가).
void main() {
  Map<String, dynamic> base(Map<String, dynamic> extra) => {
        'uid': 'u1',
        'role': 'member',
        'center_id': 'c1',
        'member_id': 'm1',
        ...extra,
      };

  group('MeResponseDto.fromJson — name (계약 v2.2)', () {
    test('name이 오면 그대로 담는다', () {
      expect(MeResponseDto.fromJson(base({'name': '김민지'})).name, '김민지');
    });

    test('name 키 누락 → null (미연결 계정·조회 실패·구버전 서버의 정상 응답)', () {
      final dto = MeResponseDto.fromJson(base({}));

      expect(dto.name, isNull);
      // 나머지 필드는 그대로 — 이름이 없다고 세션 부트스트랩이 무너지면 안 된다.
      expect(dto.uid, 'u1');
      expect(dto.memberId, 'm1');
    });

    test('name: null → null (계약은 omitempty지만 방어)', () {
      expect(MeResponseDto.fromJson(base({'name': null})).name, isNull);
    });

    test('member_id가 없어도(미연결) name만 오는 응답을 파싱한다', () {
      final dto = MeResponseDto.fromJson({
        'uid': 'u1',
        'role': 'staff',
        'center_id': 'c1',
        'name': '박관장',
      });

      expect(dto.memberId, isNull);
      expect(dto.name, '박관장');
    });

    test('공백뿐인 name도 파싱 단계에선 원문 그대로 — 정규화는 세션 경계의 몫', () {
      // DTO가 임의로 trim/승격하면 "서버가 뭘 줬는지"를 잃는다. 표시용 정규화는
      // AuthRepositoryImpl.loadSession()이 CoachLabel 한 곳에서 끝낸다.
      expect(MeResponseDto.fromJson(base({'name': '  '})).name, '  ');
    });
  });
}
