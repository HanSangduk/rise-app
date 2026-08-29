import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/my/domain/hold_rules.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

/// 일시정지 신청 시트 — 여행·부상 시. 홀딩 상한은 센터 정책 실값(GET /v1/center)으로
/// 표기하고, 패스가 2개 이상이면 대상 패스를 드롭다운으로 고른다(기본 = 대표 패스).
///
/// 상한·구간 판정은 [HoldRules]가 서버(`HoldPass` → `ValidateHoldWindow` →
/// `ValidateNewHold`)와 **같은 순서로** 하고, 이 시트는 그 결과를 문구로 옮기고
/// 버튼을 잠그기만 한다. 잔여 표시(“남은 일시정지 27일 · 1회”)도 같은 모듈
/// ([HoldRules.allowance])에서 나오므로 "남았다고 써 있는데 거부당한다"가 생길 수 없다.
Future<void> showHoldRequestSheet(
  BuildContext context, {
  required List<PassDetail> passes,
  required String initialPassId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // 루트 Navigator에 띄운다 — 기본값(false)이면 셸 내부 Navigator에 올라가
    // **하단 탭바가 시트와 스크림 위에 남는다**(실기기 점검에서 발견, P09).
    // 모달이 뜬 채로 다른 탭을 누를 수 있어 확정 전 화면을 벗어나게 된다.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) =>
        _HoldRequestSheet(passes: passes, initialPassId: initialPassId),
  );
}

class _HoldRequestSheet extends ConsumerStatefulWidget {
  const _HoldRequestSheet({required this.passes, required this.initialPassId});
  final List<PassDetail> passes;
  final String initialPassId;

  @override
  ConsumerState<_HoldRequestSheet> createState() => _HoldRequestSheetState();
}

class _HoldRequestSheetState extends ConsumerState<_HoldRequestSheet> {
  // 대표 패스가 후보에 없으면 첫 후보로 정규화 — 드롭다운 미조작 제출 방어.
  // 후보가 하나도 없으면 null이고, 그때 시트는 신청 폼 대신 이유를 띄운다.
  late String? _selectedPassId = _initialSelection();
  DateTime? _from;
  DateTime? _to;
  final _reasonController = TextEditingController();
  bool _submitting = false;

  /// 서버가 돌려준 거부/실패 문구. 사전 판정([_rejection])과 구분해 둔다 —
  /// 입력을 고치면 사라져야 하는 값이라 패스·날짜가 바뀔 때 지운다.
  String? _error;

  /// 홀딩 대상 후보 — 서버 `HoldPass`가 받는 **active만**([HoldRules.canRequestFor]).
  ///
  /// 예전엔 `isActive || isScheduled`였고, 게다가 후보가 비면 원본 목록으로
  /// 폴백했다. 그 폴백이 만료·환불 패스를 다시 드롭다운에 올려 **서버가 확실히
  /// 400을 줄 신청**에 살아 있는 버튼을 줬다(환불 패스는 유효기간이 남은 채로
  /// 실제로 존재한다 — `RefundPass`는 status만 바꾼다).
  List<PassDetail> get _eligiblePasses => HoldRules.candidates(widget.passes);

  String? _initialSelection() {
    final candidates = _eligiblePasses;
    if (candidates.isEmpty) return null;
    return candidates.any((p) => p.id == widget.initialPassId)
        ? widget.initialPassId
        : candidates.first.id;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  /// 지금 입력으로 신청하면 서버가 거부하는가 — 날짜가 덜 찼으면 아직 판정하지 않는다
  /// (미입력은 "거부"가 아니라 "미완성"이라 제출 시 안내한다).
  HoldRejected? _rejection(PassDetail pass, CenterPolicy policy) {
    if (_from == null || _to == null) return null;
    final state = HoldRules.evaluate(
      pass: pass,
      from: _from!,
      to: _to!,
      // 서버 `today()`가 KST 고정 — 기기 로컬 날짜로 재면 해외 체류 시 하루 어긋난다.
      today: DateFmt.todayKst(),
      maxHoldsPerPass: policy.maxHoldsPerPass,
      maxHoldTotalDays: policy.maxHoldTotalDays,
    );
    return state is HoldRejected ? state : null;
  }

  @override
  Widget build(BuildContext context) {
    final policy =
        ref.watch(centerPolicyProvider).value ?? CenterPolicy.fallback;
    final passes = _eligiblePasses;
    if (passes.isEmpty) return _NoCandidateBody(passes: widget.passes);
    final selected = passes.firstWhere(
      (p) => p.id == _selectedPassId,
      orElse: () => passes.first,
    );
    final rejection = _rejection(selected, policy);
    // 살아 있는 문구는 하나만 — 사전 판정이 있으면 그게 지금의 진실이고,
    // 없을 때만 직전 서버 응답을 남긴다.
    final blockingMessage = rejection?.message ?? _error;
    final allowance = HoldRules.allowance(
      pass: selected,
      maxHoldsPerPass: policy.maxHoldsPerPass,
      maxHoldTotalDays: policy.maxHoldTotalDays,
    );
    final datesComplete = _from != null && _to != null;

    // 사유 입력 시 키보드가 올라오면 작은 화면에서 overflow — 스크롤로 흡수.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '일시정지 신청',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            // 두 번째 줄은 신청 **전에** 말해야 하는 규칙이다: 서버는 조기 종료(재개)된
            // 홀딩도 횟수 상한에 계속 포함한다(`domain.ValidateNewHold` + pass.go 주석
            // "조기 종료(Resume)된 홀딩도 횟수 상한에 포함된다"). 늘어난 유효기간만
            // 말하면 "짧게 여러 번 나눠 쓰면 되겠다"로 읽히는데, 그건 상한에 먼저 걸린다.
            // 상한 수치("최대 2회/30일")는 여기서 말하지 않는다 — 아래 잔여 요약이
            // 같은 숫자를 들고 있어서, 두 곳에 겹치면 위계가 사라진다.
            '여행·부상 시 · 일시정지 기간만큼 유효기간이 늘어나요\n'
            '중간에 재개하면 안 쉰 날짜는 반납되지만, 이번 1회는 쓴 것으로 남아요',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 10),
          // 잔여 요약 — "얼마나 남았는가"는 신청 전에 가장 먼저 답해야 할 질문이라
          // 무채색 한 줄이 아니라 자리(면)를 준다. 문구와 아래 판정이 같은 모듈
          // ([HoldRules.allowance])·같은 정책 값에서 나오므로 "남았다고 써 있는데
          // 거부당한다"가 생길 수 없다. 잔여 0이어도 폼은 남긴다 — 드롭다운의 다른
          // 패스는 잔여가 있을 수 있다.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allowance.headline,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: allowance.exhausted
                        ? AppColors.danger
                        : AppColors.ink,
                  ),
                ),
                if (allowance.detail case final detail?) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (passes.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedPassId,
              decoration: const InputDecoration(labelText: '대상 회원권'),
              // Material 기본 셰브런만 이 시트에서 튀었다 — 앱 아이콘 세트로 교체.
              icon: const RiseIcon(
                RiseIcons.chevronDown,
                size: 16,
                color: AppColors.muted,
              ),
              items: [
                for (final p in passes)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      // 코치 이름은 "어떤 회원권인지" 구분하는 꼬리표 — 퇴사 표기는
                      // 마이 탭 앵커(PassList 행)가 담당한다(pass_list.dart 주석).
                      // 이름은 정규화된 값으로만 조립한다(원본 재보간 금지).
                      CoachLabel.joinDot([
                        p.product,
                        if (CoachLabel.nameOrNull(p.trainerName)
                            case final coach?)
                          '$coach 코치',
                      ]),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (v) {
                      if (v == null) return;
                      // 대상이 바뀌면 직전 서버 응답은 더 이상 이 화면의 진실이 아니다.
                      setState(() {
                        _selectedPassId = v;
                        _error = null;
                      });
                    },
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: '시작일',
                  value: _from,
                  onTap: () => _pickDate(isFrom: true, pass: selected),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DateField(
                  label: '종료일',
                  value: _to,
                  onTap: () => _pickDate(isFrom: false, pass: selected),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(hintText: '사유(선택)'),
          ),
          const SizedBox(height: 12),
          // 버튼 위 **단일 메시지 슬롯** — 항상 정확히 하나가 살아 있다:
          //   거부/서버 실패(danger) → 날짜 미입력 안내(muted) → 신청 미리보기(중립).
          // 버튼이 잠기는 모든 원인(신청 중은 라벨이 말한다)에 인접 설명이 붙어
          // "왜 안 눌리는지 모르는" 죽은 버튼이 생기지 않는다. 미입력과 거부는
          // 상호배타다 — 사전 판정은 두 날짜가 있어야 돈다([_rejection]).
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: blockingMessage != null
                ? Text(
                    blockingMessage,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  )
                : !datesComplete
                ? Text(
                    _incompleteHint,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  )
                : Text(
                    _previewLabel(allowance),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
          ),
          RiseButton(
            label: _submitting ? '신청 중…' : '신청하기',
            expand: true,
            // 서버가 거부할 게 확실하면 버튼을 잠근다 — 이 앱의 다른 자리
            // (PassOnHoldForSlot·NotYetValid·퇴사 코치·잔여 0)와 같은 원칙이다.
            // 날짜 미입력도 잠근다 — 위 슬롯의 muted 안내가 다음 행동을 상시로
            // 말하고 있어서, 눌러서 에러를 받는 것보다 한 스텝 짧다.
            onPressed: (_submitting || rejection != null || !datesComplete)
                ? null
                : () => _submit(selected, policy),
          ),
        ],
      ),
    );
  }

  /// 날짜 미입력 상태의 다음 행동 안내 — 이미 고른 쪽은 다시 시키지 않는다.
  String get _incompleteHint {
    if (_from == null && _to == null) return '시작일과 종료일을 선택하면 신청할 수 있어요';
    if (_to == null) return '종료일을 선택하면 신청할 수 있어요';
    return '시작일을 선택하면 신청할 수 있어요';
  }

  /// 두 날짜가 유효할 때의 신청 미리보기 — 양끝 포함 일수(9/1~9/10 = 10일)는
  /// 사용자 직관(9일)과 어긋나기 쉬워서, 계산값을 제출 전에 미리 보여준다.
  /// 이 슬롯이 보이는 시점엔 사전 판정이 통과한 뒤라 잔여 계산이 음수일 수 없다.
  String _previewLabel(HoldAllowance allowance) {
    final requested = HoldRules.durationDays(_from!, _to!);
    final remaining = allowance.remainingDays;
    if (remaining == null) {
      // 일수 무제한 — 없는 상한을 지어내지 않는다.
      return '이번 신청: $requested일 정지';
    }
    final after = remaining - requested;
    return after == 0
        ? '이번 신청: $requested일 정지 — 남은 일수를 모두 사용해요'
        : '이번 신청: $requested일 정지 · 신청 후 남은 $after일';
  }

  static DateTime _clampDate(DateTime v, DateTime lo, DateTime hi) =>
      v.isBefore(lo) ? lo : (v.isAfter(hi) ? hi : v);

  Future<void> _pickDate({
    required bool isFrom,
    required PassDetail pass,
  }) async {
    // 하한은 센터(KST) 오늘 — 서버가 `next.From < today(KST)`를 400으로 막으므로
    // 기기 로컬 날짜가 KST보다 하루 뒤처진 지역(미주 등)에선 "오늘"을 골라도 거부됐다.
    final today = DateFmt.todayKst();
    var first = today;
    var last = today.add(const Duration(days: 365));
    if (isFrom) {
      // 시작일 상한은 유효기간까지 — 서버 `next.From > validUntil` 거부의 미러라
      // "앱이 더 엄해지는" 위반이 아니고, 고를 수 없는 날짜를 피커에서 지운다.
      // (종료일은 조이지 않는다 — 정지 기간만큼 연장되므로 validUntil을 넘을 수 있다.)
      final validUntil = DateTime(
        pass.validUntil.year,
        pass.validUntil.month,
        pass.validUntil.day,
      );
      if (validUntil.isBefore(last)) last = validUntil;
      if (last.isBefore(first)) {
        last = first; // 깨진 데이터 방어 — 피커는 first > last에서 assert.
      }
    } else {
      // 종료일 하한은 시작일 — 역전 조합 자체를 피커에서 만들 수 없게.
      if (_from case final from?) first = from;
    }
    final picked = await showDatePicker(
      context: context,
      // initialDate는 [first, last] 밖이면 피커가 assert — 현재값에서 시작하되 보정한다.
      initialDate: _clampDate(
        (isFrom ? _from : _to ?? _from) ?? today,
        first,
        last,
      ),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        // 시작일을 종료일 뒤로 다시 골랐다 — 기간 전체를 옮기려는 조작이라 기존
        // 종료일은 폐기하고, 버튼 위 안내("종료일을 선택하면…")가 다음 행동을 말한다.
        if (_to case final to? when picked.isAfter(to)) _to = null;
      } else {
        _to = picked;
      }
      // 날짜를 고치면 직전 서버 응답은 낡은 값 — 사전 판정이 다시 말한다.
      _error = null;
    });
  }

  Future<void> _submit(PassDetail pass, CenterPolicy policy) async {
    if (_from == null || _to == null) {
      setState(() => _error = '시작일과 종료일을 선택해주세요');
      return;
    }
    // 버튼이 이미 잠기지만 이중 방어 — 위젯 배치가 바뀌어도 서버가 거부할 신청은
    // 나가지 않는다(동의 시트의 `if (widget.consentUnknown) return;`과 같은 관문).
    if (_rejection(pass, policy) case final rejected?) {
      setState(() => _error = rejected.message);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(myViewModelProvider.notifier)
        .requestHold(
          passId: pass.id,
          from: _from!,
          to: _to!,
          reason: _reasonController.text.isEmpty
              ? null
              : _reasonController.text,
        );
    if (!mounted) return;
    switch (result) {
      case Ok():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          riseSnackBar('일시정지 신청 완료 — 기간만큼 유효기간이 연장돼요', kind: RiseSnackKind.ok),
        );
      case Err(:final failure):
        setState(() {
          _submitting = false;
          _error = failure.message;
        });
    }
  }
}

/// 신청 가능한 회원권이 하나도 없을 때의 시트 본문 — 폼을 띄우지 않는다.
///
/// 진입점(PassList 행)이 이미 active 없는 상태를 비활성으로 막지만, 여기서도
/// 같은 판정을 한다: 폼을 띄워 놓고 제출 순간에만 거부하면 회원은 날짜까지
/// 다 채운 뒤에야 안 된다는 걸 알게 된다.
class _NoCandidateBody extends StatelessWidget {
  const _NoCandidateBody({required this.passes});

  /// 마이 탭이 들고 있는 회원권 전부(전부 active가 아님) — 이유를 구체적으로 말하려고 받는다.
  final List<PassDetail> passes;

  /// 회원권이 하나뿐이면 그 상태로 정확히 말한다(“9/1부터 시작하는 회원권이에요”).
  /// 여러 개면 어느 것을 지목해도 나머지엔 틀린 말이라 공통 사실만 말한다.
  String get _reason {
    if (passes.isEmpty) return '등록된 회원권이 없어요 — 센터에 문의해주세요';
    if (passes.length == 1) {
      return HoldPassNotActive(
        passes.first.status,
        validFrom: passes.first.validFrom,
      ).message;
    }
    return '이용 중인 회원권이 없어요 — 일시정지는 이용 중인 회원권만 신청할 수 있어요';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '일시정지 신청',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _reason,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          RiseButton(
            label: '닫기',
            expand: true,
            style: RiseButtonStyleKind.outline,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
            ),
            Text(
              value == null ? '선택' : DateFmt.isoDate(value!),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
