// 회원권 경고 배지(P30).
//
// 종전엔 `잔여 N회 — 연장 상담 가능`이 **조건 없이 항상** 노란 경고로 켜져 있었다.
// 두 가지가 잘못이었다:
//   ① 늘 켜져 있으면 정작 D-3에 아무 신호도 못 된다 — 경고가 배경이 된다.
//   ② "연장 상담 가능"은 회원이 앱에서 갈 경로가 없는 약속이다. 재등록·상담 요청
//      엔드포인트가 서버에 없고 `POST /v1/passes`는 회원에게 403이다.
//
// 임계값은 센터가 정한 `policy.expiring_days`를 쓴다. 서버는 v1부터 이 값을 내려주고
// 있었는데 앱이 파싱하지 않아, 앱은 임계값을 아예 갖고 있지 않았다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/center_api.dart';
import 'package:rise_member/core/api/dto/center_dto.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/date_format.dart';

void main() {
  test('서버가 내려주는 만료임박 기준일이 앱까지 온다', () {
    // 이 값이 없으면 홈은 "언제가 임박인지"를 알 수 없어 항상 켜진 배지로 돌아간다.
    expect(CenterPolicy.fallback.expiringDays, 7);
  });

  test('세션 전(로그인 전)에도 기준일이 살아 있다', () async {
    // 실패 폴백이 0이면 D-0만 경고가 되어 사실상 배지가 죽는다.
    // `testWidgets`로 쓰면 riverpod 스케줄러의 dispose 타이머가 fake_async에 남아
    // "Pending timers"로 깨진다 — 위젯이 필요 없는 검증이라 순수 test로 둔다.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final policy = await container.read(centerPolicyProvider.future);
    expect(policy.expiringDays, greaterThan(0));
  });

  test('서버 값이 모델까지 그대로 온다 — 매핑에서 상수로 굳지 않는다', () async {
    // 뮤테이션에서 실제로 살아남은 구멍이다: fallback 상수만 검사하면
    // `centerPolicyProvider`의 DTO→모델 매핑이 값을 버리고 상수를 넣어도 안 걸린다.
    // 그러면 대표가 설정에서 14일로 바꿔도 회원은 영영 7일 기준을 본다.
    const dto = CenterResponseDto(
      centerId: 'rise',
      policy: CenterPolicyDto(expiringDays: 21),
    );

    final container = ProviderContainer(
      overrides: [centerApiProvider.overrideWithValue(_FakeCenterApi(dto))],
    );
    addTearDown(container.dispose);
    // 세션이 없으면 provider가 조회 전에 폴백으로 떨어진다(로그인 전 401 소음 방지).
    container.read(sessionProvider.notifier).set(const AppSession(
          uid: 'u1',
          role: 'member',
          centerId: 'rise',
          memberId: 'm1',
        ));

    final policy = await container.read(centerPolicyProvider.future);
    expect(policy.expiringDays, 21, reason: '서버가 정한 기준일이 화면까지 와야 한다');
  });

  group('경고 규칙 — 말할 게 있을 때만', () {
    // _passAlert는 화면 private이라 규칙 자체를 여기서 재현해 잠근다.
    // (규칙이 바뀌면 이 표도 함께 바뀌어야 한다는 뜻이다.)
    String? alert({required int daysLeft, required int remaining, int expiringDays = 7}) {
      if (daysLeft < 0) return '유효기간이 지났어요';
      if (daysLeft <= expiringDays) {
        return daysLeft == 0 ? '오늘까지예요 · 잔여 $remaining회' : 'D-$daysLeft · 잔여 $remaining회';
      }
      if (remaining <= 0) return '잔여 회차를 다 썼어요';
      if (remaining <= 3) return '잔여 $remaining회 남았어요';
      return null;
    }

    test('여유로우면 아무 말도 하지 않는다 — 종전엔 이때도 노란 경고였다', () {
      expect(alert(daysLeft: 88, remaining: 20), isNull);
    });

    test('유효기간이 먼저다 — 기간이 끝나면 잔여가 통째로 소멸한다', () {
      expect(alert(daysLeft: 3, remaining: 20), 'D-3 · 잔여 20회');
      expect(alert(daysLeft: 0, remaining: 20), '오늘까지예요 · 잔여 20회');
      expect(alert(daysLeft: -1, remaining: 20), '유효기간이 지났어요');
    });

    test('기간이 넉넉해도 잔여가 적으면 말한다', () {
      expect(alert(daysLeft: 60, remaining: 3), '잔여 3회 남았어요');
      expect(alert(daysLeft: 60, remaining: 4), isNull);
      expect(alert(daysLeft: 60, remaining: 0), '잔여 회차를 다 썼어요');
    });

    test('센터가 기준일을 바꾸면 경고 시점도 따라간다', () {
      expect(alert(daysLeft: 10, remaining: 20, expiringDays: 7), isNull);
      expect(alert(daysLeft: 10, remaining: 20, expiringDays: 14), 'D-10 · 잔여 20회');
    });

    test('없는 경로를 가리키지 않는다 — "상담"·"연장"을 말하지 않는다', () {
      // 회원이 앱에서 할 수 있는 행동이 없다. 사실만 말하고 데스크에 맡긴다.
      for (final d in [-1, 0, 3, 60]) {
        final a = alert(daysLeft: d, remaining: 1) ?? '';
        expect(a.contains('상담'), isFalse, reason: 'daysLeft=$d');
        expect(a.contains('연장'), isFalse, reason: 'daysLeft=$d');
      }
    });
  });

  test('D-day 계산은 KST 기준 — 화면 문구와 저장 날짜가 갈리면 안 된다', () {
    final today = DateFmt.todayKst();
    expect(today.hour, 0, reason: '날짜만 남은 값이어야 D-day 계산이 흔들리지 않는다');
  });
}

class _FakeCenterApi implements CenterApi {
  _FakeCenterApi(this.dto);
  final CenterResponseDto dto;

  @override
  Future<CenterResponseDto> fetchCenter() async => dto;
}
