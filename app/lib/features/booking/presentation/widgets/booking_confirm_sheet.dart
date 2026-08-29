import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';

/// 예약 확정 시트 — 슬롯을 탭해도 바로 예약하지 않고 요약을 보여준 뒤 확정.
/// (wodshot D38과 동일 원칙: 짧은 확인 액션은 라우트가 아니라 바텀시트.)
Future<void> showBookingConfirmSheet(
  BuildContext context, {
  required String slotKey,
  required String passId,
  required String timeLabel,
  required String trainerLabel,
  required String productLabel,
  StaffDto? trainer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // 루트 Navigator에 띄운다 — 기본값(false)이면 셸 내부 Navigator에 올라가
    // **하단 탭바가 시트와 스크림 위에 남는다**(실기기 점검에서 발견, P09).
    // 모달이 뜬 채로 다른 탭을 누를 수 있어 확정 전 화면을 벗어나게 된다.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _BookingConfirmSheet(
      slotKey: slotKey,
      passId: passId,
      timeLabel: timeLabel,
      trainerLabel: trainerLabel,
      productLabel: productLabel,
      trainer: trainer,
    ),
  );
}

class _BookingConfirmSheet extends ConsumerStatefulWidget {
  const _BookingConfirmSheet({
    required this.slotKey,
    required this.passId,
    required this.timeLabel,
    required this.trainerLabel,
    required this.productLabel,
    this.trainer,
  });

  final String slotKey;
  final String passId;
  final String timeLabel;
  final String trainerLabel;
  final String productLabel;

  /// 코치 소형 아바타용(P05) — 스태프 캐시 미적중이면 null(아바타 없이 표시).
  final StaffDto? trainer;

  @override
  ConsumerState<_BookingConfirmSheet> createState() => _BookingConfirmSheetState();
}

class _BookingConfirmSheetState extends ConsumerState<_BookingConfirmSheet> {
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          const Text('예약 확인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(widget.timeLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Row(
            children: [
              // 코치 소형 아바타(P05) — 어떤 코치의 수업인지 시각적으로 한 번 더 확인.
              if (widget.trainer case final t?) ...[
                TrainerAvatar(
                  name: t.name,
                  photoUrl: t.profile.photoUrl,
                  colorHex: t.color,
                  size: 18,
                  // 퇴사면 흑백/무채색 — trainerLabel의 "(퇴사)" 텍스트와 짝(계약 v2.0).
                  inactive: t.isInactive,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  // 상품명이 비면 "정혜린 코치 (퇴사) · "처럼 구분자만 남는다
                  // — 빈 조각은 버리고 잇는다(CoachLabel.joinDot).
                  CoachLabel.joinDot([widget.trainerLabel, widget.productLabel]),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
            ),
          RiseButton(
            label: _submitting ? '예약 중…' : '예약 확정',
            expand: true,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(bookingViewModelProvider.notifier)
        .book(slotKey: widget.slotKey, passId: widget.passId);
    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop();
      case Err(:final failure):
        setState(() {
          _submitting = false;
          _error = failure.message;
        });
    }
  }
}
