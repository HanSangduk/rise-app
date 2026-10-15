import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/widgets/legal_document_link.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/underline_link.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';

/// 로그인 1단계 — 전화번호 입력 (목업 step-phone).
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  /// 입력창을 항상 state.phone에서 시작한다. 매번 빈 컨트롤러를 만들면
  /// 코드 화면에서 뒤로 왔을 때 칸은 비어 보이는데 state.phone은 옛 번호로 남아
  /// "인증번호 받기"가 **보이지 않는 번호**로 나갔다(화면과 상태 불일치).
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(authViewModelProvider).phone);

  /// 종료 확인 다이얼로그 중복 방지 — 백을 연타하면 다이얼로그가 겹쳐 쌓인다.
  bool _exitAsked = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authViewModelProvider);

    // 로그인 첫 화면 — 되돌아갈 화면이 없고 라우터 스택도 1장이라, 막지 않으면
    // 시스템 백이 곧바로 앱을 끈다(입력하던 번호도 함께 날아간다). 한 번 되묻는다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // 대기실과 같은 "최소 뷰포트, 넘치면 스크롤" 골격(P72 C2). 고정 Column이던 시절엔
        // 안내 한 줄·링크 한 줄을 더할 자리가 없어 P59 B5가 법정 링크를 **유보**했다 —
        // 320×568 @1.35에서 키보드까지 올라오면 넘친다는 이유였다. 골격을 바꾸면 그 사유가
        // 사라진다. 전화번호를 수집하는 화면이 바로 여기인데 근거 문서로 가는 길이 한 화면
        // 뒤(대기실)에만 있었다(개인정보보호법 §15② — 읽어야 할 시점은 수집 **전**이다).
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 34, 20, 34),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: math.max(0, viewport.maxHeight - 68)),
                child: IntrinsicHeight(
            child: Column(
              children: [
                const SizedBox(height: 26),
                RichText(
                  text: const TextSpan(
                    style: AppTypography.logo,
                    children: [
                      TextSpan(text: 'RISE '),
                      TextSpan(text: 'CONDITIONING', style: TextStyle(color: AppColors.brand)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '라이즈 컨디셔닝 · 회원 앱',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.center,
                  // 이 앱의 유일한 자동완성 자리(P72) — 번호는 OS가 안다. 앱 전체에
                  // autofillHints 사용이 0건이었다.
                  autofillHints: const [AutofillHints.telephoneNumber],
                  onChanged: (v) => ref.read(authViewModelProvider.notifier).setPhone(v),
                  decoration: const InputDecoration(hintText: '휴대폰 번호 (010-1234-5678)'),
                ),
                const SizedBox(height: 8),
                // **이 앱이 성립하는 전제를 여기서 처음 말한다**(P72 C2). 종전엔 그 전제가
                // 화면에 처음 등장하는 곳이 대기실의 연락 카드 힌트, 즉 **이미 실패한 뒤**였다.
                // 오타·가족 번호·회사폰으로 SMS 왕복을 마친 다음에야 "그 번호가 아니었다"를
                // 알았고, 되돌리려면 로그아웃 + 재인증 전체 왕복이었다.
                //
                // 뒷문장을 빼지 않는다 — 앞문장만 두면 아직 회원이 아닌 사람이 문 앞에서
                // 돌아선다. 실제로는 인증 뒤 가입 요청 경로가 열려 있다.
                const Text(
                  '센터 데스크에 등록한 번호로 인증해주세요.\n아직 회원이 아니어도 인증 뒤 가입 요청할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: AppColors.muted),
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
                  label: state.submitting ? '전송 중…' : '인증번호 받기',
                  expand: true,
                  // 코드 화면에서 시작한 재전송이 아직 날아가는 중일 수 있다 —
                  // 라벨은 실제로 하는 일(전송)만 말하되 중복 발송은 막는다.
                  onPressed: state.busy ? null : _submit,
                ),
                const Spacer(),
                // 수집 **전**에 근거 문서로 가는 길(개인정보보호법 §15②). 대기실 푸터와 같은
                // 위젯·같은 44dp 규약을 쓴다. 계정 삭제는 없다 — 아직 만들어진 계정이 없다.
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RiseUnderlineLink(
                      label: '이용약관',
                      onTap: () => openLegalDocument(context, LegalLinks.terms),
                    ),
                    const Text(' · ',
                        style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    RiseUnderlineLink(
                      label: '개인정보처리방침',
                      onTap: () => openLegalDocument(context, LegalLinks.appPrivacy),
                    ),
                  ],
                ),
              ],
            ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final outcome = await ref.read(authViewModelProvider.notifier).sendCode();
    if (!mounted) return;
    switch (outcome) {
      case SendCodeOutcome.codeSent:
        context.go('/login/code');
      // 안드로이드 즉시 인증 — 로그인도 매칭도 이미 끝났다. 코드 화면으로 보내면
      // 오지 않을 인증번호를 기다리게 되므로 곧바로 센터 확인으로 건너뛴다.
      case SendCodeOutcome.verified:
        context.go('/login/center-confirm');
      case SendCodeOutcome.failed:
        break; // 사유는 state.error가 이 화면에 인라인으로 보여준다.
    }
  }

  /// 종료 확인 — 시스템 백이 곧장 앱을 끄지 않도록 한 단계 되묻는다.
  Future<void> _confirmExit() async {
    if (_exitAsked) return;
    _exitAsked = true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('앱을 종료할까요?'),
        content: const Text('로그인을 아직 마치지 않았어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속하기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('종료'),
          ),
        ],
      ),
    );
    _exitAsked = false;
    if (exit ?? false) await SystemNavigator.pop();
  }
}
