import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/utils/coach_label.dart';

// 계약 v2.0(직원 생애주기) 표기 규약을 고정한다. 두 부류의 실제 결함을 막는다:
//  ① 이름 미해석이 그대로 렌더된 자리 — 홈 헤더 "담당  코치"(빈자리),
//     회원권 카드 "PT 20회 · "(꼬리 구분자), 내 예약 "1:1 · ".
//     null만 검사하던 곳들은 서버가 name: ""을 주면 그대로 통과시켰다.
//  ② 퇴사 표기 문구가 화면마다 갈리는 것 — 접미사는 이 유틸에만 있어야 한다.
void main() {
  group('CoachLabel.resolve', () {
    test('이름이 있으면 그대로', () {
      expect(CoachLabel.resolve('정혜린'), '정혜린');
    });

    test('null → 기본 폴백 "담당"', () {
      expect(CoachLabel.resolve(null), '담당');
    });

    test('빈 문자열·공백도 null과 같은 미해석으로 본다', () {
      expect(CoachLabel.resolve(''), '담당');
      expect(CoachLabel.resolve('   '), '담당');
    });

    test('폴백은 호출부 문맥에 맞게 바꿀 수 있다(슬롯 배지는 "코치")', () {
      expect(CoachLabel.resolve(null, fallback: '코치'), '코치');
    });

    test('앞뒤 공백은 다듬어 붙인다(" · " 조립 시 이중 공백 방지)', () {
      expect(CoachLabel.resolve(' 정혜린 '), '정혜린');
    });

    test('폴백도 같은 규칙으로 정규화한다 — 공백뿐인 폴백은 살아남지 못한다', () {
      // 온보딩 매칭 카드는 `fallback: trainerName ?? ''`로 넘긴다. 폴백을 trim하지
      // 않던 시절엔 공백뿐인 이름이 non-null로 통과해 "담당    코치" + 빈 이니셜
      // 아바타(TrainerAvatar는 isEmpty만 본다)가 됐다.
      expect(CoachLabel.resolve(null, fallback: '   '), '');
      expect(CoachLabel.resolve('  ', fallback: ''), '');
      expect(CoachLabel.resolve('  ', fallback: ' 정혜린 '), '정혜린');
    });
  });

  group('CoachLabel.nameOrNull — 정규화의 단일 지점', () {
    test('미해석(null·""·공백)은 전부 null', () {
      expect(CoachLabel.nameOrNull(null), isNull);
      expect(CoachLabel.nameOrNull(''), isNull);
      expect(CoachLabel.nameOrNull('   '), isNull);
    });

    test('해석되면 **정규화된** 값이 나온다 — 호출부가 원본을 다시 볼 일이 없게', () {
      // 이게 반쪽이던 시절의 결함: isUnresolved()는 trim해서 통과시키는데 그 뒤
      // 보간은 원본이라 " 정혜린 " → "담당  정혜린  코치"가 렌더됐다.
      expect(CoachLabel.nameOrNull(' 정혜린 '), '정혜린');
      expect(CoachLabel.nameOrNull('정혜린'), '정혜린');
    });

    test('정상 이름은 값이 그대로 — 공백 없는 이름의 렌더는 바뀌지 않는다', () {
      for (final raw in ['정혜린', '김태오', 'Kim']) {
        expect(CoachLabel.nameOrNull(raw), raw);
        expect(CoachLabel.resolve(raw), raw);
      }
    });
  });

  group('CoachLabel.joinDot — 매달린 구분자', () {
    test('빈 조각은 구분자째 사라진다', () {
      // 이름 쪽만 막아서는 부족했다: 상품명이 ""면 " · 정혜린"(홈 회원권 카드),
      // "정혜린 코치 (퇴사) · "(예약 확정 시트)처럼 반대쪽이 매달렸다.
      expect(CoachLabel.joinDot(['', '정혜린']), '정혜린');
      expect(CoachLabel.joinDot(['정혜린 코치 (퇴사)', '']), '정혜린 코치 (퇴사)');
      expect(CoachLabel.joinDot([null, null]), '');
      expect(CoachLabel.joinDot(['   ', '1:1', null]), '1:1');
    });

    test('모든 조각이 있으면 기존 표기 그대로', () {
      expect(CoachLabel.joinDot(['PT 20회', '정혜린']), 'PT 20회 · 정혜린');
      expect(
        CoachLabel.joinDot(['8/23 (일) 14:00', '1:1', '정혜린']),
        '8/23 (일) 14:00 · 1:1 · 정혜린',
      );
    });

    test('조각도 정규화된다 — 공백 이름이 이중 공백을 만들지 않는다', () {
      expect(CoachLabel.joinDot(['PT 20회', ' 정혜린 ']), 'PT 20회 · 정혜린');
    });
  });

  group('CoachLabel.isUnresolved', () {
    test('null·빈 문자열·공백만 true', () {
      expect(CoachLabel.isUnresolved(null), isTrue);
      expect(CoachLabel.isUnresolved(''), isTrue);
      expect(CoachLabel.isUnresolved('  '), isTrue);
      expect(CoachLabel.isUnresolved('정혜린'), isFalse);
    });
  });

  group('CoachLabel.tag', () {
    test('현직이면 원문 그대로 — 표기가 새로 붙지 않는다', () {
      expect(CoachLabel.tag('담당 정혜린 코치', inactive: false), '담당 정혜린 코치');
    });

    test('퇴사면 문구 끝에 "(퇴사)"', () {
      expect(CoachLabel.tag('담당 정혜린 코치', inactive: true), '담당 정혜린 코치 (퇴사)');
    });
  });

  group('CoachLabel.inline', () {
    test('괄호 안 좁은 자리는 "·  퇴사" 형태 — 괄호 중첩을 피한다', () {
      expect(CoachLabel.inline('정혜린', inactive: true), '정혜린 · 퇴사');
      expect('내 코치 (${CoachLabel.inline('정혜린', inactive: true)})', '내 코치 (정혜린 · 퇴사)');
    });

    test('현직이면 이름만', () {
      expect(CoachLabel.inline('정혜린', inactive: false), '정혜린');
    });
  });

  group('실제 렌더 문자열 회귀 — 빈자리·꼬리 구분자', () {
    // 호출부는 이제 판정과 보간을 한 값(nameOrNull)으로 처리한다 — 아래 헬퍼들은
    // 각 화면의 조립 규칙을 그대로 옮긴 것이다(home_screen · my_bookings_list).
    String header(String? memberName, String? coach, {bool inactive = false}) {
      final name = CoachLabel.nameOrNull(coach);
      final who = CoachLabel.nameOrNull(memberName);
      return CoachLabel.joinDot([
        who == null ? '라이즈 컨디셔닝' : '$who 님',
        name == null ? null : CoachLabel.tag('담당 $name 코치', inactive: inactive),
      ]);
    }

    test('홈 헤더: 이름 미해석이면 "담당  코치" 대신 문구를 통째로 생략', () {
      expect(header('람', null), '람 님');
      expect(header('람', ''), '람 님');
      expect(header('람', '정혜린'), '람 님 · 담당 정혜린 코치');
      expect(header('람', '정혜린', inactive: true), '람 님 · 담당 정혜린 코치 (퇴사)');
    });

    test('홈 헤더: 공백 낀 이름도 이중 공백 없이 붙는다', () {
      expect(header('람', ' 정혜린 '), '람 님 · 담당 정혜린 코치');
      expect(header(' 람 ', ' 정혜린 ', inactive: true), '람 님 · 담당 정혜린 코치 (퇴사)');
    });

    test('홈 헤더: 회원 이름이 비어도 퇴사 앵커는 살아남는다', () {
      // 예전엔 memberName이 비면 센터명만 남고 "담당 X 코치 (퇴사)"가 통째로
      // 사라져, 이름을 못 받은 회원만 담당 코치 변경을 홈에서 볼 수 없었다.
      expect(header(null, '정혜린', inactive: true), '라이즈 컨디셔닝 · 담당 정혜린 코치 (퇴사)');
      expect(header('  ', '정혜린'), '라이즈 컨디셔닝 · 담당 정혜린 코치');
      expect(header(null, null), '라이즈 컨디셔닝');
    });

    test('내 예약 행: 이름 미해석이면 " · " 꼬리째 사라진다', () {
      String row(String? name) => CoachLabel.joinDot(['1:1', name]);

      expect(row(null), '1:1');
      expect(row(''), '1:1');
      expect(row('정혜린'), '1:1 · 정혜린');
      expect(row(' 정혜린 '), '1:1 · 정혜린');
    });
  });
}
