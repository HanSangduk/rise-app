import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';

part 'lobby_auto_check.g.dart';

/// 대기실 자동 확인의 기본 간격(P69 H1). **`null`이면 자동 확인 전체가 꺼진다** — 마운트 즉시
/// 1회도 없다.
///
/// provider로 둔 이유는 위젯 테스트다(plan C 3-e): `pumpAndSettle`은 살아 있는 타이머가 있는
/// 한 절대 settle되지 않아, 주기 타이머 하나가 대기실 테스트 31건을 전부 타임아웃시킨다. 테스트
/// 하네스가 `overrideWithValue(null)` 한 줄로 끄고, 자동 확인 전용 테스트만 `tester.pump(30s)`로
/// 틱을 진행한다. `centerContactProvider`의 `retry: _noRetry`와 같은 교훈이다.
@Riverpod(keepAlive: true)
Duration? lobbyAutoCheckInterval(Ref ref) => const Duration(seconds: 30);

/// 대기실 자동 확인 — "센터가 승인하면 연결돼요"를 **참으로 만드는** 위젯(P69 H1).
///
/// 이 위젯이 생기기 전 대기실은 "자동으로 연결돼요"라고 말하면서 실제로는 사용자가 버튼을
/// 눌러야만 승인 여부를 알았다(푸시·폴링·앱 재개 재확인이 전부 없었다). 규칙:
///  · 마운트 시 서버가 pending을 **확답하지 않은** 상태([JoinRequestTrace.unknown])면 즉시 1회 —
///    코드 인증 직후 경로는 서버를 물은 적이 없다. 확답 직후(requestJoin 성공·복원)는 방금 물은
///    것과 같으므로 첫 확인은 주기 뒤.
///  · 포그라운드에서만 주기 실행. 실패하면 30 → 60 → 120초로 물러나고(그 이상 늘리지 않는다 —
///    대기실은 짧게 머무는 화면이라 5분 간격은 "안 한다"와 같다), 성공하면 30초로 돌아온다.
///  · `resumed` 복귀 즉시 1회 — 백그라운드에서 승인됐을 수 있고 OS는 타이머를 제때 깨우지 않는다
///    (`time_boundary_builder.dart`와 같은 관례). 백그라운드에선 타이머를 놓는다.
///  · `state.busy`면 그 틱은 건너뛴다(실패로 세지 않는다) — 사용자가 방금 수동 확인·가입 요청을
///    눌렀다면 그쪽이 같은 서버 답을 받는다(plan B Q10).
///  · 자동 틱은 스낵바를 띄우지 않는다 — 30초마다 토스트는 소음이다. `connected`만 [onConnected]로
///    화면에 위임한다(수동 확인과 같은 `context.go('/home')` 경로).
///
/// 401은 여기서 다루지 않는다 — dio 인터셉터가 세션을 비우고 리스너가 로그인으로 보낸다.
class LobbyAutoCheck extends ConsumerStatefulWidget {
  const LobbyAutoCheck({super.key, required this.onConnected});

  /// 자동 확인이 `connected`를 받았다 — 화면이 홈으로 보낸다.
  final VoidCallback onConnected;

  @override
  ConsumerState<LobbyAutoCheck> createState() => _LobbyAutoCheckState();
}

class _LobbyAutoCheckState extends ConsumerState<LobbyAutoCheck> with WidgetsBindingObserver {
  /// 백오프 상한(기본 간격의 배수) — 30초 기준 120초.
  static const _maxBackoffFactor = 4;

  Timer? _timer;
  int _failures = 0;
  bool _foreground = true;
  bool _ticking = false;

  Duration? get _interval => ref.read(lobbyAutoCheckIntervalProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 테스트·초기화 직후엔 lifecycleState가 null일 수 있다 — 모르면 포그라운드로 본다.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_interval == null) return;

    if (ref.read(authViewModelProvider).joinRequestTrace != JoinRequestTrace.pending) {
      // 마운트 중에 뷰모델 상태를 바꾸면 이 화면이 build 도중 리빌드 표시된다 — 프레임 뒤로 미룬다.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
    } else {
      _schedule();
    }
  }

  @override
  void dispose() {
    // 반드시 먼저 취소한다 — 홈으로 떠난 뒤 타이머가 살아 있으면 mounted=false에 checkConnection이
    // 날아가고, 위젯 테스트는 "A Timer is still pending"으로 죽는다.
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // 백그라운드에선 놓는다 — OS가 정시에 깨워 주지 않고, 복귀 즉시 확인이 그 몫을 대신한다.
      _foreground = false;
      _cancel();
      return;
    }
    _foreground = true;
    if (_interval != null) _tick();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 다음 틱 하나만 예약한다(주기 타이머가 아니라 일회성) — 백오프가 틱마다 달라지기 때문.
  void _schedule() {
    _cancel();
    final interval = _interval;
    if (interval == null || !_foreground || !mounted) return;
    final factor = math.min(1 << _failures, _maxBackoffFactor);
    _timer = Timer(interval * factor, _tick);
  }

  Future<void> _tick() async {
    if (!mounted || _ticking) return;
    // 이 화면 위에 다른 라우트(가입 요청 시트·삭제 확인 다이얼로그)가 떠 있으면 건너뛴다 —
    // 그 위에서 connected를 받아 `context.go('/home')`를 실행하면 시트가 라우트 없이 고아로
    // 남고, 이름을 적던 사람은 화면이 바뀐 이유를 모른다. 시트가 닫히면 다음 틱이 확인한다.
    // busy 스킵과 같은 취급(실패 아님 — 백오프 없음).
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _schedule();
      return;
    }
    if (ref.read(authViewModelProvider).busy) {
      // 겹쳐서 건너뜀은 실패가 아니다 — 백오프도 실패 시각도 건드리지 않는다.
      _schedule();
      return;
    }
    _ticking = true;
    final result = await ref.read(authViewModelProvider.notifier).checkConnection();
    _ticking = false;
    if (!mounted) return;
    switch (result) {
      case ConnectionCheck.connected:
        _cancel();
        widget.onConnected();
        return;
      case ConnectionCheck.notYet:
        _failures = 0;
      case ConnectionCheck.failed:
        _failures++;
    }
    _schedule();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
