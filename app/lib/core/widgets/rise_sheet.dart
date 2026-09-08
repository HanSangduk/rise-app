import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// 앱의 모든 모달 바텀시트는 이 함수로 연다(P54).
///
/// **왜 `useSafeArea: true`로는 안 되는가** — 이게 이 파일이 존재하는 이유다.
/// Flutter의 그 옵션은 하단을 **의도적으로 제외**한다:
///
/// ```dart
/// // material/bottom_sheet.dart
/// Widget bottomSheet = useSafeArea
///     ? SafeArea(bottom: false, child: content)   // ← bottom: false
///     : MediaQuery.removePadding(context: context, removeTop: true, child: content);
/// ```
///
/// dartdoc도 "the bottom sheet extends all the way to the bottom of the screen,
/// **including any system intrusions**"라고 명시한다. 즉 켜도 하단 침범은 그대로다.
///
/// **실제 증상**: targetSdk 36에서 edge-to-edge는 강제이고(Android 16은 opt-out
/// 플래그마저 무시한다) 시스템 바가 콘텐츠 위에 겹친다. 종전 시트들은 하단 여백을
/// `viewInsets.bottom + 20`으로 잡았는데 `viewInsets`는 **키보드만** 센다. 그래서
/// 키보드가 없는 시트에서 CTA가 내비게이션 바 아래로 들어갔다 — 3버튼 내비 28dp,
/// iOS 홈 인디케이터 14dp. `RiseButton` 실높이가 42dp이므로 3버튼 모드에서는
/// 버튼의 눌리는 영역이 14dp만 남았다(예약 확정·동의 저장·계약 서명이 그 경우다).
/// 키보드가 올라온 상태에서는 정확했다 — Android는 IME가 뜨면 `viewInsets`에
/// 내비바 높이를 함께 담기 때문이고, 그래서 입력 시트에서는 안 드러났다.
///
/// **해법**: 시트 안쪽이 보는 `viewInsets.bottom`을 "키보드 ∪ 시스템 바"로 바꿔
/// 주입한다. 그러면 기존 호출부의 `viewInsets.bottom + 20` 코드가 **한 줄도 바뀌지
/// 않은 채** 정답이 된다. 위젯 트리를 건드리지 않으므로 diff가 작고 회귀 위험이 낮다.
///
/// **더하지 않고 `max`인 이유**: `viewInsets`에 내비바가 이미 포함되는 그 성질 때문에
/// 더하면 키보드 위로 내비바 높이만큼 CTA가 붕 뜬다(실측: 키보드 300dp 조건에서
/// `max`는 여백 20dp, `+`는 68dp). MediaQuery의 항등식
/// `padding.bottom = max(0, viewPadding.bottom - viewInsets.bottom)`을 뒤집으면
/// `viewInsets.bottom + padding.bottom ≡ max(viewInsets.bottom, viewPadding.bottom)`이라
/// 이 값이 곧 "아래에서 침범해 오는 높이"의 정의가 된다.
///
/// `useSafeArea: true`는 그래도 켠다 — 하단엔 무효지만 **상단 노치와 좌우**를 맡고,
/// 끄면 `MediaQuery.removePadding(removeTop: true)`가 걸려 시트 안에 `SafeArea`를
/// 넣어도 상단에 효과가 없다(화면 80%를 채우는 계약 상세·코치 목록이 그 경우).
///
/// `useRootNavigator: true`는 P09에서 얻은 규약이다 — 셸 내부 Navigator로 열면
/// 시트 뒤로 하단 탭바가 남아 다른 탭으로 빠져나갈 수 있다. 래퍼가 강제해서
/// 다음 시트에서 다시 빠지지 않게 한다.
///
/// **시트 본문에서 `padding.bottom`을 또 더하지 말 것** — 여기서 이미 합쳤으므로
/// 이중 계상이 된다. `test/tool/sheet_guard_test.dart`가 막고 있다.
///
/// ## `submitting` — 제출 중 잠금(P56 M1)
///
/// 제출 중인 시트를 닫으면 **실패가 통째로 사라진다.** 에러는 시트 **안** 인라인이라
/// (`_error` 텍스트), 요청이 날아가는 동안 회원이 시트를 아래로 쓸거나 스크림을 탭하면
/// State가 dispose되고 응답은 `if (!mounted) return`에 삼켜진다. 인바디 6칸을 채우고
/// 저장 → 드래그 → 서버 400 → **입력도 사라지고 아무 말도 없다.** 반대로 성공했는데
/// 성공 스낵바만 사라지는 쪽은 회원이 "안 됐나?" 하고 **같은 요청을 다시 보낸다**
/// (예약 중복·홀딩 중복 — 서버가 409로 막더라도 에러 화면을 한 번 더 본다).
///
/// `showModalBottomSheet`의 `isDismissible`·`enableDrag`는 **라우트 생성 시점에 굳는다**
/// — 제출 시작 순간에 켤 수 없다. 그래서 래퍼가 시트 본문을 감싸 세 경로를 직접 막는다:
///
///  · 스크림 탭·시스템 백 — `PopScope(canPop: false)`. 둘 다 `Navigator.maybePop`을
///    타므로 라우트의 `popDisposition`(= PopScope 등록)에 걸린다.
///  · 아래로 쓸기 — **PopScope로는 안 막힌다.** `BottomSheet.onClosing`이
///    `Navigator.pop`(maybePop이 아니다)을 부른다(SDK `bottom_sheet.dart`). 그래서
///    잠금 중에는 시트 본문 바깥쪽에 세로 드래그 인식기를 하나 더 둔다 — 히트 테스트
///    경로상 시트의 `_BottomSheetGestureDetector`보다 **안쪽**이라 같은 포인터 이벤트를
///    먼저 받고, 슬롭을 넘는 순간 먼저 승리해 시트의 드래그가 아레나에서 진다.
///    본문 안 스크롤(더 안쪽)은 그보다 먼저 받으므로 잠금 중에도 스크롤은 된다.
///
/// 신호는 [ValueListenable]로 받는다 — 시트 State의 `_submitting`이 **이 노티파이어
/// 하나**여야 한다(getter로 읽고 `.value`로 쓴다). 필드 bool을 따로 두고 미러링하면
/// 실패 분기 한 곳에서 미러를 빠뜨리는 순간 **시트가 영원히 잠긴다** — 이 저장소가
/// 가장 싫어하는 막다른 길이라 저장소를 하나로 못 박는다.
///
/// 잠금은 **닫는 제스처만** 막는다. 시트 본문의 `Navigator.pop`(성공 후 닫기)은
/// `pop`이라 PopScope를 거치지 않으므로 그대로 동작한다.
Future<T?> showRiseSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool isDismissible = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  ValueListenable<bool>? submitting,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    backgroundColor: backgroundColor,
    shape: shape,
    builder: (sheetContext) {
      final mq = MediaQuery.of(sheetContext);
      // `builder(sheetContext)`로 부르면 안 된다 — 자식이 받는 context가 이
      // MediaQuery **위쪽**이라 주입한 값을 못 읽는다(호출부는 `MediaQuery.of`를
      // 쓰므로 조용히 종전 값으로 되돌아간다). `Builder`가 아래쪽 context를 만든다.
      Widget body = Builder(builder: builder);
      if (submitting != null) {
        body = _SubmitLock(submitting: submitting, child: body);
      }
      return MediaQuery(
        data: mq.copyWith(
          viewInsets: mq.viewInsets.copyWith(
            bottom: math.max(mq.viewInsets.bottom, mq.viewPadding.bottom),
          ),
        ),
        child: body,
      );
    },
  );
}

/// [showRiseSheet]의 `submitting` 잠금 본체 — 파일 헤더 "`submitting`" 절 참조.
///
/// 트리 모양은 잠금 여부와 **무관하게 같다**(GestureDetector를 항상 두고 콜백만
/// 켜고 끈다). 잠글 때만 감싸는 식으로 부모 위젯 타입이 바뀌면 자식 서브트리가 통째로
/// 재생성되어 시트 State(입력값·`_submitting`)가 날아간다 — 그러면 잠그는 순간 잠금
/// 신호 자체가 사라지는 자기모순이 된다.
class _SubmitLock extends StatelessWidget {
  const _SubmitLock({required this.submitting, required this.child});

  final ValueListenable<bool> submitting;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: submitting,
      child: child,
      builder: (context, locked, child) {
        return PopScope(
          canPop: !locked,
          child: GestureDetector(
            // opaque: 본문의 빈 여백(색 없는 Padding 등)에서 시작한 쓸기도 잡는다.
            // 안 잠겼을 때는 인식기가 없어 히트만 되고 아무 일도 하지 않는다 —
            // 시트 자체의 드래그(조상)는 종전처럼 그대로 받는다.
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: locked ? _swallowStart : null,
            onVerticalDragUpdate: locked ? _swallowUpdate : null,
            onVerticalDragEnd: locked ? _swallowEnd : null,
            child: child,
          ),
        );
      },
    );
  }

  // 아레나에서 이기기 위한 인식기 — 실제로는 아무것도 하지 않는다.
  static void _swallowStart(DragStartDetails _) {}
  static void _swallowUpdate(DragUpdateDetails _) {}
  static void _swallowEnd(DragEndDetails _) {}
}
