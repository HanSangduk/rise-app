import 'package:flutter/material.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

/// 동의 관리 시트 — 일반/민감정보 동의 토글 + 철회. PUT /v1/members/{id}로 저장.
///
/// [consentUnknown] = 마이 탭 로드 때 동의 조회가 실패해 [consent]가 하드코딩
/// 기본값(false/false)이라는 뜻(MySummary.consentFailed). true면 이 시트는
/// **읽기 전용**이 된다 — 아래 [_ConsentSheetState.build] 주석 참조.
Future<void> showConsentToggles(
  BuildContext context, {
  required ConsentState consent,
  bool consentUnknown = false,
}) {
  // 제출 중 잠금 신호(P56 M1) — 철회 PUT이 날아가는 동안 시트를 쓸어 내리면 실패 스낵바가
  // 죽은 context로 가고, 회원은 철회됐다고 믿는다(rise_sheet.dart 헤더).
  final submitting = ValueNotifier(false);
  return showRiseSheet<void>(
    context,
    submitting: submitting,
    builder: (_) => _ConsentSheet(
      consent: consent,
      consentUnknown: consentUnknown,
      submitting: submitting,
    ),
  );
}

class _ConsentSheet extends ConsumerStatefulWidget {
  const _ConsentSheet({
    required this.consent,
    required this.submitting,
    this.consentUnknown = false,
  });
  final ConsentState consent;
  final bool consentUnknown;

  /// 제출 중 신호 — 래퍼의 잠금과 같은 객체.
  final ValueNotifier<bool> submitting;

  @override
  ConsumerState<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends ConsumerState<_ConsentSheet> {
  late bool _general = widget.consent.general;
  late bool _sensitive = widget.consent.sensitive;

  /// 저장소는 [widget.submitting] 하나다(rise_sheet.dart `submitting` 절).
  bool get _submitting => widget.submitting.value;

  @override
  void dispose() {
    widget.submitting.dispose();
    super.dispose();
  }

  /// 지금 저장하면 **켜져 있던 동의가 꺼지는** 항목들의 결과 문구(없으면 빈 목록).
  ///
  /// 철회는 비가역 액션에 가깝다 — 서버가 `revoked_at`을 감사 기록으로 남기고
  /// (`api/service.go` `normalizeConsentTransition`), sensitive는 그 즉시
  /// 신규 저장이 400으로 막힌다(`domain/member.go` `SensitiveConsentValid`,
  /// `CreateInbody`·`CreateBodyPhoto`). 그래서 결과를 **구체적으로** 말한다.
  ///
  /// 문구는 서버가 실제로 하는 일만 적는다: 조회는 막지 않으므로(회원 본인 읽기는
  /// 동의와 무관 — `checkBodyPhotoAccess`의 member 분기, `ListInbody`의 스코프 검사만)
  /// "이미 저장된 기록은 그대로 볼 수 있어요"가 참이고, general 철회는 서버가 값만
  /// 기록할 뿐 어떤 API도 잠그지 않으므로 잠긴다고 쓰지 않는다.
  List<String> get _revocations => [
        if (widget.consent.sensitive && !_sensitive)
          '· 민감정보 동의를 끄면 인바디·체형 기록을 새로 저장할 수 없어요 — 이미 저장된 기록은 그대로 볼 수 있어요.',
        if (widget.consent.general && !_general)
          '· 일반 이용 동의를 끄면 철회로 기록돼요 — 예약·결제 등 서비스 이용의 근거가 되는 동의예요.',
      ];

  @override
  Widget build(BuildContext context) {
    // 현재 동의 상태를 모르면 이 시트는 아무것도 저장하지 않는다.
    //
    // PUT /v1/members/{id}는 화면 값을 그대로 반영하고, 서버는 sensitive
    // true→false를 **철회로 기록한다**(revoked_at). 조회가 실패해 스위치가 전부
    // 꺼진 채로 뜬 상태에서 "저장"을 누르면, 회원이 토글을 건드리지 않았어도
    // 실제 동의가 철회되고 인바디·체형사진 저장이 잠긴다. 그래서 "모른다"일 때는
    // 토글과 저장을 함께 잠그고 다시 불러오기만 남긴다.
    final unknown = widget.consentUnknown;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('동의 관리', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            unknown
                // 원인을 지어내지 않고 다음 행동만 안내한다(RiseErrorView 규약).
                ? '지금은 동의 상태를 확인하지 못했어요 — 아래 화면이 실제 값이 아닐 수 있어\n'
                    '변경을 저장하지 않아요. 다시 불러온 뒤 바꿔주세요'
                : '민감정보(인바디·체형사진) 동의는 언제든 철회할 수 있어요',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: unknown ? AppColors.danger : AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _general,
            title: const Text('일반 이용 동의', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: const Text('예약·결제 등 서비스 이용에 필요한 개인정보', style: TextStyle(fontSize: 10.5)),
            onChanged: unknown ? null : (v) => setState(() => _general = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sensitive,
            title: const Text('민감정보(인바디·체형사진) 동의', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: const Text('체형 분석 촬영·인바디 기록에 필요해요', style: TextStyle(fontSize: 10.5)),
            onChanged: unknown ? null : (v) => setState(() => _sensitive = v),
          ),
          // 끄기로 바꾼 순간 결과를 미리 말한다 — "저장"을 누르기 전에 보여야
          // 확인 다이얼로그가 놀람이 아니라 재확인이 된다(계약 서명 시트의
          // 동의 체크박스와 같은 방어 수준).
          if (!unknown && _revocations.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.danger, width: 1.5),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                _revocations.join('\n'),
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger, height: 1.5),
              ),
            ),
          const SizedBox(height: 6),
          if (unknown)
            RiseButton(
              label: '다시 불러오기',
              expand: true,
              style: RiseButtonStyleKind.outline,
              onPressed: _reload,
            )
          else
            RiseButton(
              label: _submitting ? '저장 중…' : '저장',
              expand: true,
              onPressed: _submitting ? null : _submit,
            ),
        ],
      ),
    );
  }

  /// 재시도 경로 — 마이 탭을 새로 로드하고 시트를 닫는다. 시트 안에서 결과를
  /// 기다렸다가 스스로 되살아나면 "저장 가능/불가"가 시트 안에서 두 번 바뀌어
  /// 회원이 무엇을 보고 있는지 헷갈린다. 갱신된 배지를 보고 다시 열게 한다.
  void _reload() {
    ref.read(myViewModelProvider.notifier).refresh();
    Navigator.of(context).pop();
  }

  /// 철회가 섞여 있으면 한 번 더 묻는다 — 켜는 방향만 있으면 묻지 않는다.
  /// 이 앱에서 확인을 받는 다른 비가역 액션(예약 취소·번호 재입력)과 같은 형식.
  Future<bool> _confirmRevocation() async {
    final revocations = _revocations;
    if (revocations.isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      // 시트와 같은 이유로 루트 Navigator에 띄운다(하단 탭바가 스크림 위에 남지 않게).
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('동의를 철회할까요?'),
        content: Text(
          '${revocations.join('\n\n')}\n\n철회한 시각이 서버에 기록돼요. 다시 켜면 바로 풀려요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('그대로 두기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('철회하기'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _submit() async {
    // 버튼 자체가 렌더되지 않지만 이중 방어 — 이 한 줄이 "조회 실패 시 저장 금지"의
    // 마지막 관문이다(위젯 배치가 바뀌어도 PUT은 나가지 않는다).
    if (widget.consentUnknown) return;
    // 확인은 PUT 전에 — 되돌리려면 다시 켜는 요청을 한 번 더 보내야 하고,
    // 그때도 `revoked_at`을 남긴 감사 기록 자체는 지워지지 않는다.
    if (!await _confirmRevocation()) return;
    if (!mounted) return;
    setState(() => widget.submitting.value = true);
    final result =
        await ref.read(myViewModelProvider.notifier).updateConsent(general: _general, sensitive: _sensitive);
    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop();
      case Err(:final failure):
        setState(() => widget.submitting.value = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(riseSnackBar(failure.message, kind: RiseSnackKind.danger));
    }
  }
}
