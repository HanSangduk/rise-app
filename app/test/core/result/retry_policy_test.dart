// 전역 재시도 정책 규약(P46).
//
// 이 정책이 없던 동안 "아직 회원권이 없어요"가 뜨기까지 **38초** 걸렸다. Riverpod
// 기본 정책이 도메인 Failure를 네트워크 오류처럼 10번 재시도했고, 재시도 중에는
// AsyncLoading이 흘러 화면이 계속 스피너였다(실기기 Play 빌드에서 발견).
// 그래서 "재시도해도 답이 바뀌지 않는 실패는 즉시 넘긴다"를 여기서 못 박는다.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/retry_policy.dart';

void main() {
  group('확정된 도메인 실패는 재시도하지 않는다 — 즉시 화면으로', () {
    // 서버가 이미 답을 확정해 내려준 것들. 다시 물어도 같은 답이 온다.
    const settled = <Failure>[
      EmptyPassesFailure(),
      RejectedFailure('만석이에요'),
      ConflictFailure('같은 날 기록이 이미 있어요'),
      AuthFailure(),
      MemberNotLinkedFailure(),
      ValidationFailure('번호 형식이 아니에요'),
      CacheFailure(),
      UnknownFailure(),
    ];

    for (final f in settled) {
      test('${f.runtimeType} — 첫 시도부터 재시도 없음', () {
        expect(
          appRetry(0, f),
          isNull,
          reason: '${f.runtimeType}를 재시도하면 사용자는 답을 아는 채로 기다린다',
        );
      });
    }
  });

  group('네트워크 실패만 재시도한다 — 다만 짧게', () {
    test('초반 시도는 재시도한다 — 일시적 끊김은 넘길 수 있다', () {
      expect(appRetry(0, const NetworkFailure()), isNotNull);
      expect(appRetry(1, const NetworkFailure()), isNotNull);
      expect(appRetry(2, const NetworkFailure()), isNotNull);
    });

    test('3회에서 멈춘다 — 기본 10회(38초)를 그대로 쓰지 않는다', () {
      expect(appRetry(3, const NetworkFailure()), isNull);
      expect(appRetry(9, const NetworkFailure()), isNull);
    });

    test('전체 대기가 2초를 넘지 않는다 — 원인 화면이 곧 떠야 한다', () {
      var total = Duration.zero;
      for (var i = 0; ; i++) {
        final d = appRetry(i, const NetworkFailure());
        if (d == null) break;
        total += d;
      }
      expect(total, lessThan(const Duration(seconds: 2)),
          reason: '실측 총 대기: $total');
    });
  });

  group('Failure가 아닌 예외는 기본 정책에 맡긴다', () {
    test('예기치 못한 예외는 재시도한다 — 일시적일 수 있다', () {
      expect(appRetry(0, TimeoutException('느림')), isNotNull);
    });

    test('Error는 재시도하지 않는다 — 코드 버그는 다시 해도 같다', () {
      // Riverpod 기본 정책이 거르는 자리. 우리 정책이 그 필터를 우회하지 않는지 고정.
      expect(appRetry(0, StateError('버그')), isNull);
    });
  });
}
