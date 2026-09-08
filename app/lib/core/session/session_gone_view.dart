import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';

/// 세션 소멸 전환 뷰·촬영 화면의 **탈출 버튼 라벨** — 착지(`sessionEndRoute`)와 같은 축으로
/// 갈린다(P64 검증 반영). 연결 해제(notLinked)는 대기실로 가는데 버튼이 '로그인 화면으로'라
/// 말하면 회원은 SMS 재인증을 각오하고 누른다 — 가는 곳을 버튼이 말해야 한다.
String sessionGoneEscapeLabel(SessionEndReason reason) => switch (reason) {
      SessionEndReason.notLinked => '연결 상태 확인하러 가기',
      SessionEndReason.signedOut ||
      SessionEndReason.unauthorized ||
      SessionEndReason.deleted =>
        '로그인 화면으로',
    };

/// 셸이 그려진 채 세션이 사라졌을 때 4탭이 에러 뷰 대신 그리는 **전환 뷰**(P64).
///
/// 이 순간 `app.dart`의 세션 리스너가 이유대로 착지 화면으로 보내는 중이다 — 보통
/// 한 프레임 안에 사라진다. 그래서 스피너만 그리고 **[다시 시도]를 두지 않는다**:
/// 그 버튼은 뷰모델을 다시 돌릴 뿐 세션을 만들지 못해, 눌러도 같은 화면이 돌아온다.
///
/// [escapeAfter] 뒤에 탈출 버튼([sessionGoneEscapeLabel])을 낸다. 리스너가 어떤 이유로 이동하지
/// 못하면(라우터 미마운트 등) 회원이 스피너에 갇히는데, 이 버튼은 재시도와 달리
/// **세션을 요구하지 않는 탈출구**다. 착지는 리스너와 같은 규칙(`sessionEndRoute`)을
/// 따른다 — 연결 해제로 비워진 세션을 여기서만 전화번호 화면으로 보내면 안 된다.
class SessionGoneView extends ConsumerStatefulWidget {
  const SessionGoneView({super.key, this.escapeAfter = const Duration(seconds: 3)});

  /// 탈출 버튼이 나타나기까지의 시간. 즉시 내면 정상 전환의 한 프레임에 버튼이
  /// 번쩍인다.
  final Duration escapeAfter;

  @override
  ConsumerState<SessionGoneView> createState() => _SessionGoneViewState();
}

class _SessionGoneViewState extends ConsumerState<SessionGoneView> {
  Timer? _timer;
  bool _showEscape = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.escapeAfter, () {
      if (mounted) setState(() => _showEscape = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  SessionEndReason get _reason =>
      ref.read(sessionProvider.notifier).lastEndReason ?? SessionEndReason.unauthorized;

  void _escape() {
    // 위젯 테스트처럼 라우터 없이 띄운 경우엔 갈 곳이 없다 — 조용히 무시.
    GoRouter.maybeOf(context)?.go(sessionEndRoute(_reason));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.brand),
          if (_showEscape) ...[
            const SizedBox(height: 18),
            RiseButton(label: sessionGoneEscapeLabel(_reason), small: true, onPressed: _escape),
          ],
        ],
      ),
    );
  }
}
