import 'package:flutter/material.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/consult/presentation/consult_providers.dart';

/// 재등록 요청 시트(계약 v2.20, P42) — 보내는 건 의사 표시 하나다. 결제·상품·가격은
/// 여기 없다(데스크 상담의 몫 — 앱은 "손들었다"를 전달할 뿐, 추천안 §의도적으로 안 하는 것).
Future<void> showConsultRequestSheet(BuildContext context) {
  // 제출 중 잠금 신호(P56 M1) — 요청이 날아가는 동안 닫히면 409("이미 보낸 요청이
  // 있어요")조차 못 보고 회원은 또 보낸다(rise_sheet.dart 헤더).
  final submitting = ValueNotifier(false);
  return showRiseSheet<void>(
    context,
    submitting: submitting,
    builder: (_) => _ConsultRequestSheet(submitting: submitting),
  );
}

class _ConsultRequestSheet extends ConsumerStatefulWidget {
  const _ConsultRequestSheet({required this.submitting});

  /// 제출 중 신호 — 래퍼의 잠금과 같은 객체.
  final ValueNotifier<bool> submitting;

  @override
  ConsumerState<_ConsultRequestSheet> createState() =>
      _ConsultRequestSheetState();
}

class _ConsultRequestSheetState extends ConsumerState<_ConsultRequestSheet> {
  final _noteController = TextEditingController();

  /// 저장소는 [widget.submitting] 하나다(rise_sheet.dart `submitting` 절).
  bool get _submitting => widget.submitting.value;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    widget.submitting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 키보드가 올라오면 작은 화면에서 overflow — 스크롤로 흡수(hold 시트와 동일).
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
            '재등록 요청',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            // 무엇이 일어나는지 정확히 — 결제가 아니라 연락이다. 기대를 여기서 맞춰야
            // "요청했는데 왜 회원권이 안 생기지"가 안 생긴다.
            '요청을 보내면 센터에서 등록된 연락처로 연락드려요\n결제·등록은 센터에서 상담 후 진행돼요',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteController,
            maxLength: 200, // 서버 상한 미러(consultNoteMaxRunes)
            decoration: const InputDecoration(
              hintText: '남길 말(선택) — 예: 주 2회로 다시 하고 싶어요',
              counterText: '', // 짧은 폼에서 0/200 카운터는 소음 — 상한 초과는 입력 자체가 막힌다
            ),
          ),
          const SizedBox(height: 12),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          RiseButton(
            label: _submitting ? '보내는 중…' : '요청 보내기',
            expand: true,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      widget.submitting.value = true;
      _error = null;
    });
    // 이 CTA는 전부 재등록 맥락에서 열린다 — kind는 renewal 고정(consult는 서버가
    // 받는 값이지만 앱 v1은 진입점이 재등록뿐이다).
    final result = await guardApi(
      () => ref
          .read(consultApiProvider)
          .create(kind: 'renewal', note: _noteController.text.trim()),
    );
    if (!mounted) return;
    switch (result) {
      case Ok():
        // CTA가 "요청 보냈어요" 상태로 바뀌는 출처 — 성공 후 즉시 갱신.
        ref.invalidate(myConsultRequestsProvider);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          riseSnackBar('재등록 요청을 보냈어요 — 센터에서 연락드릴 거예요', kind: RiseSnackKind.ok),
        );
      case Err(:final failure):
        // 409(이미 pending)도 서버 문구 그대로 — "이미 보낸 요청이 있어요…"가 정답 그 자체다.
        setState(() {
          widget.submitting.value = false;
          _error = failure.message;
        });
        // CTA 상태도 갱신 — 이 기기가 몰랐던 pending(다른 기기에서 보냄)이 원인일 수 있다.
        ref.invalidate(myConsultRequestsProvider);
    }
  }
}
