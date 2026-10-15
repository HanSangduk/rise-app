import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';

/// 대기실 스텝퍼(P69 H2) — "내 요청이 어디까지 갔는지"가 보이는 공항 게이트 화면.
///
/// `번호 인증 → 가입 요청 → 센터 확인 → 연결` 네 단계. 현재 단계는 [AuthState.lobbyStep]이 정하고,
/// 요청 시각은 `joinRequestedAt`이 있을 때만 붙는다(파싱 실패면 시각 없이 "가입 요청 보냄").
///
/// **"센터 확인 중"이 아니라 "기다리는 중"이다** — 센터가 보고 있는지 앱은 모른다. 로컬 기록만 있고
/// 서버가 pending을 확답하지 않았으면([requestConfirmed] false) 체크 대신 중립 표식을 찍는다 —
/// 서버 best-effort null을 "요청 없음"으로도, 로컬 기록을 "서버가 받았다"로도 그리지 않는다.
///
/// 좁은 폭(<360)이나 큰 글자 배율(≥1.2)에서는 세로 리스트로 바뀐다 — 가로 4점은 라벨이 줄바꿈되며
/// 점이 흐트러진다(320×568 @1.35가 이 앱의 실제 최소 조건). 폭은 [availableWidth]로 받는다 —
/// 화면 골격이 `IntrinsicHeight`(P56 A1)라 이 안의 `LayoutBuilder`는 intrinsic 계산에서 죽는다.
/// 화면의 바깥 `LayoutBuilder`(뷰포트)가 이미 폭을 알고 있으므로 그 값을 내려받는다.
class LobbyProgress extends StatelessWidget {
  const LobbyProgress({
    super.key,
    required this.step,
    required this.availableWidth,
    this.requestedAt,
    this.requestConfirmed = false,
    this.dense = false,
  });

  final LobbyStep step;

  /// 이 위젯이 쓸 수 있는 가로 폭(뷰포트 − 화면 좌우 패딩).
  final double availableWidth;
  final DateTime? requestedAt;

  /// 서버가 pending을 확답했는가([JoinRequestTrace.pending]) — "가입 요청 보냄"의 체크 여부.
  final bool requestConfirmed;

  /// 세로가 빠듯한 화면(320×568·배율 1.3+)에서 행간을 줄인다(P72). 트랙선은 남는다 —
  /// 진행률을 나르는 것은 간격이 아니라 선이다.
  final bool dense;

  /// "9/8 12:05" — 스텝퍼와 rejected 결과 행이 같은 표기를 쓴다.
  static String requestedAtLabel(DateTime t) => '${t.month}/${t.day} ${DateFmt.hhmm(t)}';

  /// 경과 구간 — **대기 화면은 늙지 않았다**(P72). 데스크 어드민은 24h/72h 경계로 큐를
  /// 노랗게·빨갛게 물들이는데(`JoinRequests.tsx` WAIT_WARN_MS·WAIT_DANGER_MS), 정작 앱
  /// 화면은 1분째와 3일째가 글자 하나 다르지 않았다 — 시각이 전부 절대 표기였고 힌트는
  /// 상수였다. 1분째엔 불안을 만들고 3일째엔 유일한 신호인데 눈에 띄지 않았다.
  ///
  /// **소요 시간을 약속하지 않는다**(P63/P69 C1 규약) — "보통 하루 안에 승인돼요"는 서버도
  /// 모르는 사실이다. 경과는 사실이고, 사실만 말한다. 경계는 데스크 화면과 **같은 값**을
  /// 쓴다: 두 화면이 다른 시점에 "늦었다"고 하면 회원과 데스크의 대화가 어긋난다.
  static String? elapsedLabel(DateTime requestedAt, {DateTime? now}) {
    final waited = (now ?? DateTime.now()).difference(requestedAt);
    if (waited.inHours >= 72) return '3일 넘음';
    if (waited.inHours >= 24) return '하루 넘음';
    if (waited.inHours >= 1) return '${waited.inHours}시간째';
    if (waited.inMinutes >= 1) return '${waited.inMinutes}분째';
    return null; // 방금 보냈다 — "0분째"는 말이 안 되고 불안만 만든다.
  }

  List<_StepSpec> _steps() {
    final index = switch (step) {
      LobbyStep.requested => 1,
      LobbyStep.waiting => 2,
      LobbyStep.connecting => 3,
    };
    final at = requestedAt;
    // 주 버튼과 **같은 글자로 맞추지 않는다**(P72에서 검토 후 기각): 화면 아래 CTA가
    // '가입 요청 보내기'라 글자를 맞추면 스텝퍼가 CTA를 가리킨다는 사실이 명시되지만,
    // P63이 실제 배포 사고 뒤 박은 "같은 문장을 두 번 그리지 않는다"와 정면으로 충돌한다
    // (`center_confirm_screen_test`의 구조적 못이 그 조합을 잡는다). 더 강한 규약을 남긴다.
    final requestLabel = index <= 1
        ? '가입 요청'
        : (at == null ? '가입 요청 보냄' : '가입 요청 보냄 · ${requestedAtLabel(at)}');
    return [
      const _StepSpec(label: '번호 인증', status: _StepStatus.done),
      _StepSpec(
        label: requestLabel,
        status: index == 1
            ? _StepStatus.current
            : (requestConfirmed ? _StepStatus.done : _StepStatus.doneUnconfirmed),
      ),
      _StepSpec(
        // **"확인"이 아니라 "승인"이다**(P72). 바로 아래 확인 상태 줄에 [지금 확인] 버튼이
        // 있어, 두 "확인"을 같은 것으로 읽으면 그 버튼이 "센터더러 지금 확인하게 하는 버튼"이
        // 된다 — 눌러도 "아직 승인 전"만 뜨니 "센터를 여러 번 찔렀는데 무시당했다"가 된다.
        // 실제로 그 버튼은 센터에 아무 신호도 보내지 않는다(읽기 전용 조회). 부제·힌트·상태
        // 줄·스낵바가 이미 전부 "승인"을 쓰고 있었고 스텝퍼만 그 축 밖이었다.
        // 사람이 하는 일 = 승인 / 앱이 하는 일 = 확인.
        label: index == 2
            ? [
                '센터 승인 기다리는 중',
                if (at != null)
                  if (elapsedLabel(at) case final e?) e,
              ].join(' · ')
            : '센터 승인',
        status: index < 2
            ? _StepStatus.upcoming
            : (index == 2 ? _StepStatus.current : _StepStatus.done),
      ),
      _StepSpec(
        label: index == 3 ? '연결 중' : '연결',
        status: index == 3 ? _StepStatus.current : _StepStatus.upcoming,
      ),
    ];
  }

  /// 세로 리스트로 그릴 조건 — 순수 함수(테스트가 폭·배율 조합만으로 고정한다).
  ///
  /// **임계가 360 → 400이다**(P72). [availableWidth]는 화면 폭 − 좌우 패딩 40이라 종전 경계는
  /// 기기 폭 400dp였다: 320·360·390(iPhone 14~16)·393(Pixel)은 세로, 412·430만 가로. 설계된
  /// 가로 4점 배치를 **주력 아이폰에서는 한 번도 볼 수 없었고**, 하필 가로 라벨이 10.5px로
  /// 이 화면에서 가장 작다 — "가장 작은 글자가 가장 큰 폰에만" 나오는 배치였다. 세로가 라벨
  /// 줄바꿈도 없고 트랙선으로 진행률도 보이므로 그쪽을 정본으로 굳힌다(가로는 태블릿 폭용).
  static bool isVertical({required double availableWidth, required double textScale}) =>
      availableWidth < 400 || textScale >= 1.2;

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    final vertical = isVertical(
      availableWidth: availableWidth,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    if (vertical) {
      // **마커 사이를 트랙으로 잇는다**(P72). 선이 없으면 네 개의 불릿이라 "할 일 목록"으로
      // 읽히고, 내가 4칸 중 어디에 서 있는지가 전달되지 않는다. 지나온 구간만 brand —
      // 색이 끊기는 지점이 곧 현재 위치다.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            _StepSemantics(
              spec: steps[i],
              child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _StepMarker(status: steps[i].status),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: steps[i].status == _StepStatus.upcoming
                                ? AppColors.line
                                : AppColors.brand,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: i < steps.length - 1 ? (dense ? 4 : 10) : 4,
                      ),
                      child: _StepLabel(spec: steps[i], center: false),
                    ),
                  ),
                ],
              ),
            ),
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in steps)
          Expanded(
            child: _StepSemantics(
              spec: s,
              child: Column(
                children: [
                  _StepMarker(status: s.status),
                  const SizedBox(height: 5),
                  _StepLabel(spec: s, center: true),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _StepStatus {
  done('완료'),
  // "보냈지만 서버가 아직 확답하지 않음" — 시각 표식(회색 원+점)의 뜻을 말로 옮긴다.
  doneUnconfirmed('보냄, 센터 확인 전'),
  current('현재 단계'),
  upcoming('남은 단계');

  const _StepStatus(this.semantics);

  /// 스크린리더가 라벨 뒤에 읽는 상태어 — 모양과 색으로만 나르던 정보의 음성 대응.
  final String semantics;
}

class _StepSpec {
  const _StepSpec({required this.label, required this.status});
  final String label;
  final _StepStatus status;
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({required this.status});
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    const size = 18.0;
    return switch (status) {
      _StepStatus.done => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const RiseIcon(RiseIcons.check, size: 11, color: Colors.white),
        ),
      // 보냈지만 서버 확답 전 — 체크가 아니라 중립 점. 확인 상태 줄이 "아직 확인 전"을 말한다.
      _StepStatus.doneUnconfirmed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: AppColors.line, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
          ),
        ),
      _StepStatus.current => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brand, width: 2),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
          ),
        ),
      _StepStatus.upcoming => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line, width: 1.5),
          ),
        ),
    };
  }
}

/// 한 단계를 **하나의 노드**로 읽게 만든다 — 마커와 라벨이 따로 읽히면 "체크 표시" 같은
/// 무의미한 낭독이 끼어든다(`MergeSemantics` + 마커 `ExcludeSemantics`).
class _StepSemantics extends StatelessWidget {
  const _StepSemantics({required this.spec, required this.child});
  final _StepSpec spec;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${spec.label}, ${spec.status.semantics}',
        excludeSemantics: true,
        child: child,
      );
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.spec, required this.center});
  final _StepSpec spec;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final current = spec.status == _StepStatus.current;
    final upcoming = spec.status == _StepStatus.upcoming;
    return Text(
      spec.label,
      textAlign: center ? TextAlign.center : TextAlign.start,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: center ? 11.5 : 12,
        height: 1.35,
        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
        color: upcoming ? AppColors.muted : AppColors.ink,
      ),
    );
  }
}

/// 확인 상태 줄이 기다리는 것(P72 C1) — 같은 버튼이 단계마다 다른 질문을 묻는다.
///
/// 빈 상태(`notFound`·`declined`)에도 확인 줄을 둔 이유는 그쪽이야말로 **데스크가 번호를
/// 고쳐 주기를 기다리는** 자리이기 때문이다. 종전엔 그 단계에 확인 버튼도 자동 확인도 없어,
/// 데스크가 고쳐도 회원 화면은 영영 "찾지 못했어요"였다. 다만 그때 기다리는 것은 승인이
/// 아니라 **등록**이라 꼬리 문장이 달라야 한다 — "아직 승인 전"은 보낸 적 없는 요청을
/// 가리키는 거짓말이 된다.
enum CheckAwaiting {
  /// 가입 요청을 보냈고 센터 승인을 기다린다.
  approval('아직 승인 전'),

  /// 요청 없이 데스크의 번호 등록·정정을 기다린다.
  registration('아직 등록 전');

  const CheckAwaiting(this.tail);

  /// 성공한 확인의 꼬리 — `마지막 확인 12:14 · {tail}`.
  final String tail;
}

/// 확인 상태 줄(P69 H2) — "얼마나, 어떻게 알 수 있는지"의 답.
///
/// 세 상태뿐이다: `아직 확인 전` / `마지막 확인 12:14 · 아직 승인 전` / `12:14 확인 못 함`.
/// 시각은 **성공한** GET /v1/me의 것만([AuthState.lastCheckedAt]); 실패는 별도 시각으로 갈라
/// "확인 못 함"이라고 말한다 — 실패한 호출을 "마지막 확인"으로 찍으면 문장이 거짓이다.
/// [지금 확인]은 수동 확인(스낵바 있음). 보조문은 자동 확인이 켜져 있을 때만 — 꺼진 상태에서
/// "자동으로 확인해요"는 P63이 지운 거짓 문구가 되돌아오는 것이다.
class CheckStatusLine extends StatelessWidget {
  const CheckStatusLine({
    super.key,
    this.lastCheckedAt,
    this.lastCheckFailedAt,
    required this.checking,
    required this.busy,
    required this.onCheck,
    required this.autoEnabled,
    this.awaiting = CheckAwaiting.approval,
  });

  final DateTime? lastCheckedAt;
  final DateTime? lastCheckFailedAt;
  final bool checking;
  final bool busy;
  final VoidCallback onCheck;

  /// 자동 확인이 켜져 있는가(`lobbyAutoCheckIntervalProvider != null`).
  final bool autoEnabled;

  /// 이 화면이 무엇을 기다리는가 — 성공한 확인의 꼬리 문장을 정한다(P72 C1).
  final CheckAwaiting awaiting;

  static const autoHint = '이 화면이 열려 있는 동안 자동으로 확인해요';

  /// 순수 함수 — 테스트가 시각 조합만으로 문장을 고정한다.
  static String statusText({
    DateTime? lastCheckedAt,
    DateTime? lastCheckFailedAt,
    CheckAwaiting awaiting = CheckAwaiting.approval,
  }) {
    final failed = lastCheckFailedAt;
    final checked = lastCheckedAt;
    if (failed != null && (checked == null || failed.isAfter(checked))) {
      return '${DateFmt.hhmm(failed)} 확인 못 함';
    }
    if (checked != null) return '마지막 확인 ${DateFmt.hhmm(checked)} · ${awaiting.tail}';
    return '아직 확인 전';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap: 글자 배율 1.35·320dp에서 버튼이 다음 줄로 내려간다.
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                checking
                    ? '확인 중'
                    : statusText(
                        lastCheckedAt: lastCheckedAt,
                        lastCheckFailedAt: lastCheckFailedAt,
                        awaiting: awaiting,
                      ),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            RiseButton(
              label: checking ? '확인 중…' : '지금 확인',
              small: true,
              onPressed: busy ? null : onCheck,
            ),
          ],
        ),
        if (autoEnabled) ...[
          const SizedBox(height: 4),
          const Text(
            autoHint,
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}
