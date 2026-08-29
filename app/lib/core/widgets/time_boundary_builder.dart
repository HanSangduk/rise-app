import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rise_member/core/utils/date_format.dart';

/// 시각이 **경계**를 지나는 순간 스스로 한 번 다시 그리는 빌더.
///
/// ## 왜 필요한가 (P51 실기기 결함)
///
/// 시각 판정("체크인 창이 열렸나", "이 슬롯은 지났나")은 그린 순간의 `now`로만
/// 참이다. Flutter는 시간이 흘렀다고 리빌드하지 않으므로, 회원이 화면을 켜 둔 채
/// 기다리면 판정이 **로드 시점에 굳은 채** 남는다 — 19:00 예약의 체크인 창은
/// 18:30에 열리는데 18:26에 홈을 연 회원은 18:35에도 회색 버튼을 본다. 당겨서
/// 새로고침해야 풀린다는 걸 알 방법이 없으니 데스크로 간다.
///
/// ## 설계 판단
///
///  · **주기 폴링·1분 티커가 아니라 일회성 타이머.** 경계는 미리 계산할 수 있는
///    시각들이라(창 열림 = 시작 −30분 등) 그때 딱 한 번 깨우면 된다. 1분 티커는
///    경계에서 최대 59초 늦고, 아무 일 없는 분에도 60번/시간 리빌드한다.
///  · **재평가는 로컬 계산일 뿐 — 서버를 다시 부르지 않는다.** [builder]에 새
///    `now`를 넘길 뿐이라 왕복이 0이다(홈 재조회는 5~6 왕복).
///  · **보이지 않으면 타이머를 놓는다.** 이 앱의 탭은
///    `StatefulShellRoute.indexedStack`이라 탭을 떠나도 위젯이 살아 있다
///    (`core/router/app_router.dart`). go_router가 비활성 브랜치를
///    `TickerMode(enabled: false)`로 감싸므로, 하드웨어팀이 카메라·센서에 쓴
///    판정(`bodycheck/presentation/camera_screen.dart`의 `TickerMode.valuesOf`)을
///    그대로 쓴다. `TickerMode`는
///    InheritedWidget이라 탭이 다시 활성화되면 이 위젯이 알아서 리빌드되고,
///    그 build에서 `now`를 새로 읽어 판정이 곧바로 맞춰진다.
///  · **앱 재개(resumed)에도 재평가한다.** 회원이 앱을 백그라운드에 두고 기다리는
///    쪽이 더 흔하고, OS가 재우는 동안 타이머는 제때 깨지 않는다. 화면 복귀 시점의
///    한 번의 `setState`가 그 공백을 메운다.
///
/// [boundaries]는 정렬돼 있지 않아도 되고 과거 값이 섞여도 된다 — 지금보다 뒤인
/// 것 중 **가장 이른 하나**에만 타이머를 건다. 그 경계를 지나면 다시 build가
/// 돌면서 다음 경계를 잡는다.
class TimeBoundaryBuilder extends StatefulWidget {
  const TimeBoundaryBuilder({
    super.key,
    this.boundaries = const [],
    this.atMidnight = false,
    required this.builder,
  });

  /// 다시 그려야 하는 시각들 — [DateFmt.nowKst]와 **같은 표현**(센터 KST 벽시계)
  /// 이어야 한다(`DateFmt` 클래스 주석의 시간축 규약).
  final List<DateTime> boundaries;

  /// 센터(KST) 자정마다 다시 그린다 — "오늘"에 걸린 표시(오늘 배지·D-day·홀딩
  /// 배지)용.
  ///
  /// [boundaries]에 자정을 직접 넣지 않고 플래그로 두는 이유: 그 목록은 부모의
  /// build에서 한 번 만들어지므로, 자정을 하나 넣어 두면 **한 번만** 넘어가고
  /// 다음 날엔 다시 굳는다. 이 플래그는 매 예약 시점의 `now`에서 "다음 자정"을
  /// 새로 계산하므로 며칠이 지나도 계속 따라온다.
  final bool atMidnight;

  /// `now`는 이 프레임의 [DateFmt.nowKst] — 판정을 여기서 하면 경계마다 갱신된다.
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<TimeBoundaryBuilder> createState() => _TimeBoundaryBuilderState();
}

class _TimeBoundaryBuilderState extends State<TimeBoundaryBuilder> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 반드시 먼저 취소한다 — 탭을 떠나도 트리에 남는 위젯이라(indexedStack) 로그아웃·
    // 라우트 교체로 실제 dispose될 때까지 타이머가 살아 있으면 mounted=false에
    // setState가 날아간다. 위젯 테스트의 "A Timer is still pending" 실패도 같은 뿌리.
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // 백그라운드에선 타이머를 놓는다. OS가 어차피 정시에 깨워 주지 않으므로
      // 들고 있어 봐야 부정확한 데다, 복귀 시점의 재평가가 그 몫을 대신한다.
      _timer?.cancel();
      _timer = null;
      return;
    }
    // 재개 즉시 재평가 — 백그라운드에 있는 동안 경계를 지났을 수 있다.
    // build가 새 `now`를 읽고 다음 경계를 다시 예약한다.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // valuesOf는 InheritedWidget 의존을 건다 — 탭 전환이 곧 리빌드
    // (TickerMode.of는 Flutter 3.35에서 deprecated). TickerMode가 없는 트리
    // (단위 위젯 테스트)에서는 기본값 enabled=true다.
    final visible = TickerMode.valuesOf(context).enabled;
    final now = DateFmt.nowKst();
    _schedule(now, visible);
    return widget.builder(context, now);
  }

  /// 다음 경계 하나에만 일회성 타이머를 건다(build마다 재계산 — boundaries가
  /// 바뀌거나 탭이 오갈 때 자동으로 따라온다).
  void _schedule(DateTime now, bool visible) {
    _timer?.cancel();
    _timer = null;
    if (!visible) return;

    DateTime? next;
    for (final b in widget.boundaries) {
      if (!b.isAfter(now)) continue; // 이미 지난 경계는 볼 필요 없다.
      if (next == null || b.isBefore(next)) next = b;
    }
    if (widget.atMidnight) {
      // 다음 자정 — `now`에서 매번 새로 계산한다(플래그로 둔 이유, 위 주석).
      // day+1은 DateTime이 월·연을 알아서 넘긴다.
      final midnight = DateTime(now.year, now.month, now.day + 1);
      // isAfter 검사는 boundaries 루프와 같은 이유로 남긴다: 과거 시각이 next로
      // 뽑히면 아래 Duration이 음수가 되고, 음수 타이머는 즉시 깨서 같은 값을
      // 또 예약하는 루프가 된다. day+1이라 실제로는 항상 미래지만, 이 불변식이
      // 깨지는 순간을 조용히 통과시키지 않는다.
      if (midnight.isAfter(now) && (next == null || midnight.isBefore(next))) next = midnight;
    }
    if (next == null) return;

    // +1초 여유. 정확히 경계 시각에 깨면 `nowKst()`가 밀리초 단위로 아직 경계
    // **직전**으로 읽힐 수 있고, 그러면 판정이 안 바뀐 채 같은 경계에 다시 예약돼
    // 1ms짜리 타이머가 반복된다. 1초 늦는 대신 한 번에 확실히 넘긴다.
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (mounted) setState(() {});
    });
  }
}
