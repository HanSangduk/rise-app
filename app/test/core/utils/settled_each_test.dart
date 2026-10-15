import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/utils/settled.dart';

// settleEach — 개수가 회원 이력에 비례하는 조회(패스별 원장)를 "동시에, 단 limit개씩" 부른다(P74).
// 상한이 빠지면 오래 다닌 회원일수록 연결이 한꺼번에 열리고, 직렬로 되돌리면 병렬화의 이득이 사라진다 —
// 둘 다 여기서 숫자로 드러난다.
void main() {
  test('결과는 입력 순서대로 — 끝나는 순서와 무관하다', () async {
    final items = [30, 1, 20, 5, 10];
    final out = await settleEach(items, (ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      return 'v$ms';
    }, limit: 3);
    expect(out.map((s) => s.valueOrThrow()), ['v30', 'v1', 'v20', 'v5', 'v10']);
  });

  test('동시에 도는 것은 최대 limit개, 그리고 실제로 limit개까지 겹친다', () async {
    var inFlight = 0;
    var peak = 0;
    final out = await settleEach(List.generate(10, (i) => i), (i) async {
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      inFlight--;
      return i;
    }, limit: 4);
    expect(peak, 4, reason: '상한이 없으면 10, 직렬이면 1');
    expect(out, hasLength(10));
  });

  test('실패는 그 칸만 Settled 실패로 — 던지지 않고 나머지도 끝까지 돈다', () async {
    final out = await settleEach<int, int>([1, 2, 3, 4], (i) async {
      if (i == 2) throw StateError('비동기 실패');
      if (i == 3) throw ArgumentError('동기 실패'); // async 본문 안이라 Future 실패가 된다
      return i * 10;
    }, limit: 2);
    expect(out[0].valueOrThrow(), 10);
    expect(out[1].failed, isTrue);
    expect(out[1].error, isA<StateError>());
    expect(out[2].failed, isTrue);
    expect(out[3].valueOrThrow(), 40);
  });

  test('호출 자체가 동기적으로 던져도 잡는다(데이터 소스의 인자 검증)', () async {
    Future<int> call(int i) => i == 1 ? throw ArgumentError('sync') : Future.value(i);
    final out = await settleEach([0, 1, 2], call);
    expect(out[1].failed, isTrue);
    expect(out[0].valueOrThrow(), 0);
    expect(out[2].valueOrThrow(), 2);
  });

  test('빈 목록이면 부르지 않고 빈 결과', () async {
    var calls = 0;
    final out = await settleEach(<int>[], (i) async => calls++);
    expect(out, isEmpty);
    expect(calls, 0);
  });
}
