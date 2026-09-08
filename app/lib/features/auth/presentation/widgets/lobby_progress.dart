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
  });

  final LobbyStep step;

  /// 이 위젯이 쓸 수 있는 가로 폭(뷰포트 − 화면 좌우 패딩).
  final double availableWidth;
  final DateTime? requestedAt;

  /// 서버가 pending을 확답했는가([JoinRequestTrace.pending]) — "가입 요청 보냄"의 체크 여부.
  final bool requestConfirmed;

  /// "9/8 12:05" — 스텝퍼와 rejected 결과 행이 같은 표기를 쓴다.
  static String requestedAtLabel(DateTime t) => '${t.month}/${t.day} ${DateFmt.hhmm(t)}';

  List<_StepSpec> _steps() {
    final index = switch (step) {
      LobbyStep.requested => 1,
      LobbyStep.waiting => 2,
      LobbyStep.connecting => 3,
    };
    final at = requestedAt;
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
        label: index == 2 ? '센터 확인 기다리는 중' : '센터 확인',
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
  static bool isVertical({required double availableWidth, required double textScale}) =>
      availableWidth < 360 || textScale >= 1.2;

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    final vertical = isVertical(
      availableWidth: availableWidth,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StepMarker(status: s.status),
                  const SizedBox(width: 8),
                  Expanded(child: _StepLabel(spec: s, center: false)),
                ],
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
            child: Column(
              children: [
                _StepMarker(status: s.status),
                const SizedBox(height: 5),
                _StepLabel(spec: s, center: true),
              ],
            ),
          ),
      ],
    );
  }
}

enum _StepStatus { done, doneUnconfirmed, current, upcoming }

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
        fontSize: center ? 10.5 : 11.5,
        height: 1.35,
        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
        color: upcoming ? AppColors.muted : AppColors.ink,
      ),
    );
  }
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
  });

  final DateTime? lastCheckedAt;
  final DateTime? lastCheckFailedAt;
  final bool checking;
  final bool busy;
  final VoidCallback onCheck;

  /// 자동 확인이 켜져 있는가(`lobbyAutoCheckIntervalProvider != null`).
  final bool autoEnabled;

  static const autoHint = '이 화면이 열려 있는 동안 자동으로 확인해요';

  /// 순수 함수 — 테스트가 시각 조합만으로 문장을 고정한다.
  static String statusText({DateTime? lastCheckedAt, DateTime? lastCheckFailedAt}) {
    final failed = lastCheckFailedAt;
    final checked = lastCheckedAt;
    if (failed != null && (checked == null || failed.isAfter(checked))) {
      return '${DateFmt.hhmm(failed)} 확인 못 함';
    }
    if (checked != null) return '마지막 확인 ${DateFmt.hhmm(checked)} · 아직 승인 전';
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
            Text(
              statusText(lastCheckedAt: lastCheckedAt, lastCheckFailedAt: lastCheckFailedAt),
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
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
            style: TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}
