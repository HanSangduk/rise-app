import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rise_member/core/utils/phone_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';

/// 로그인 2단계 — 인증번호 입력 (목업 step-code).
/// "인증번호 재전송"은 30초 카운트다운 후 활성(requestVerificationCode 재호출 —
/// dev 스텁에서도 동일하게 동작).
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  static const _resendCooldownSeconds = 30;

  /// phone_screen과 같은 원칙 — 컨트롤러는 state.code에서 시작해 화면과 상태를
  /// 항상 일치시킨다(빈 칸인데 옛 코드가 제출되는 일이 없게).
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(authViewModelProvider).code);
  Timer? _resendTimer;
  int _resendRemaining = _resendCooldownSeconds;

  /// 자동 진행이 진행 중(또는 이미 성공)인가 — 같은 로그인 전이가 여러 이벤트로
  /// 흘러도 매칭이 중복으로 나가지 않게 하는 화면 쪽 빗장. 실패했을 때만 푼다.
  bool _autoAdvancing = false;

  @override
  void initState() {
    super.initState();
    // 화면 진입 = 방금 발송된 상태 — 곧바로 카운트다운 시작.
    _startResendCountdown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendRemaining = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendRemaining -= 1);
      if (_resendRemaining <= 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authViewModelProvider);

    // 안드로이드 SMS 자동 회수는 codeSent **이후**에도 도착한다(정상 SMS 흐름).
    // 그때 사용자는 이미 로그인이 끝났는데도 이 화면은 오지 않을 입력을 기다리며
    // 재전송 카운트다운만 돌았다 — "확인"이 동작한다는 걸 아는 사람만 빠져나갔다.
    // 로그인 완료를 감지해 코드 확인과 **같은 경로**(매칭)로 자동 진행한다.
    //
    // 구독 수명은 이 화면이 소유한다: ref.listen은 위젯이 사라질 때 함께 끊기고,
    // signedInPhoneProvider는 autoDispose라 마지막 구독이 사라지면 Firebase
    // 스트림 구독까지 정리된다(직접 StreamSubscription을 들면 dispose 누락이 곧 누수).
    ref.listen(signedInPhoneProvider, (_, next) {
      // 로그아웃(null)·스트림 에러는 자동 진행 대상이 아니다.
      final phone = next.value;
      if (phone != null) _autoAdvance(phone);
    });
    // 재전송과 확인은 서로 다른 요청 — 진행 플래그를 나눠 쓰되(state.resending /
    // state.submitting) 동시 실행만 막는다. 한 플래그를 공유하던 시절엔 재전송
    // 중에 확인 버튼이 "확인 중…"이라고, 입력조차 않은 코드를 검증하는 척했다.
    final canResend = _resendRemaining <= 0 && !state.busy;

    // 시스템 백 = 화면 좌상단 뒤로가기와 같은 목적지(번호 입력). 막지 않으면
    // 라우터 스택이 1장이라 백이 앱을 끈다 — 인증 도중에 앱이 사라지는 셈.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goBackToPhone();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 34),
            child: Column(
              children: [
                IconButton(
                  alignment: Alignment.centerLeft,
                  // flat 라우트 + context.go 진입이라 스택이 1장 — pop()은 GoError를
                  // 던지므로 명시적으로 전화번호 화면으로 되돌린다.
                  onPressed: _goBackToPhone,
                  // RiseIcon은 IconTheme.size를 읽지 않는다 — size 명시 필수.
                  icon: const RiseIcon(RiseIcons.arrowLeft, size: 20),
                ),
                const SizedBox(height: 12),
                const Text(
                  '인증번호 입력',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.phone.isEmpty ? '입력하신 번호' : formatKoreanPhoneForDisplay(state.phone)}로 보냈어요',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  onChanged: (v) => ref.read(authViewModelProvider.notifier).setCode(v),
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 8),
                  decoration: const InputDecoration(hintText: '6자리', counterText: ''),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.error!.message,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: 12),
                RiseButton(
                  label: state.submitting ? '확인 중…' : '확인',
                  expand: true,
                  onPressed: state.busy ? null : _submit,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: canResend ? _resend : null,
                  child: Text(
                    switch ((state.resending, _resendRemaining)) {
                      (true, _) => '재전송 중…',
                      (false, final s) when s > 0 => '인증번호 재전송 ($s초 후)',
                      _ => '인증번호 재전송',
                    },
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: canResend ? AppColors.ink : AppColors.muted,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 좌상단 뒤로가기와 시스템 백의 공통 목적지.
  void _goBackToPhone() => context.go('/login');

  /// 자동 회수로 로그인이 끝난 경우 — 코드 확인과 같은 목적지로 잇는다.
  /// 뷰모델이 번호 일치·중복 매칭을 다시 검사하므로(completeAutoVerification),
  /// 여기서는 화면 전환과 재진입 빗장만 책임진다.
  Future<void> _autoAdvance(String signedInPhone) async {
    if (_autoAdvancing) return;
    _autoAdvancing = true;
    final ok = await ref
        .read(authViewModelProvider.notifier)
        .completeAutoVerification(signedInPhone);
    if (!mounted) return;
    if (ok) {
      context.go('/login/center-confirm');
      return;
    }
    // 진행 중이었거나(확인 버튼과 겹침) 매칭에 실패했다 — 빗장을 풀어 다음
    // 이벤트에 다시 기회를 준다. 그동안에도 "확인" 버튼은 그대로 살아 있다.
    _autoAdvancing = false;
  }

  Future<void> _submit() async {
    final ok = await ref.read(authViewModelProvider.notifier).verifyAndMatch();
    if (ok && mounted) context.go('/login/center-confirm');
  }

  Future<void> _resend() async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref.read(authViewModelProvider.notifier).sendCode(resend: true);
    if (!mounted) return;
    switch (outcome) {
      case SendCodeOutcome.codeSent:
        // 새 코드가 나갔으니 직전 입력은 무효 — 뷰모델이 state.code를 비우므로
        // 입력창도 같이 비워 화면과 상태를 어긋나지 않게 한다.
        _controller.clear();
        _startResendCountdown();
        messenger.showSnackBar(riseSnackBar('인증번호를 다시 보냈어요', kind: RiseSnackKind.ok));
      // 재전송이 즉시 인증으로 끝나는 경우(안드로이드 자동 회수) — 입력할 코드가
      // 없으니 이 화면에 남겨 두면 안 된다. 매칭까지 끝난 상태로 넘어간다.
      case SendCodeOutcome.verified:
        context.go('/login/center-confirm');
      case SendCodeOutcome.failed:
        break; // state.error가 화면 인라인 문구로 표시된다(카운트다운 리셋 없음).
    }
  }
}
