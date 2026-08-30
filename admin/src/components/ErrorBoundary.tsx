// 전역 에러 경계 — 렌더 도중 예외가 나면 React는 트리 전체를 언마운트한다. 경계가 없으면
// 그 결과가 **빈 흰 화면**이다: 한국어도, 무슨 일이 났는지도, 다시 시도할 방법도 없다.
// 어드민의 막다른 길 중에서 가장 완전한 막다른 길이라, 다른 어떤 에러 문구보다 먼저 필요하다.
//
// 쓰는 사람은 센터 대표 한 명이고 개발자가 아니다 — 콘솔을 열지 않고, 물어볼 상대도 없다.
// 그래서 이 카드가 사고 순간의 유일한 안내다: 무슨 일인지 / 자료는 무사한지 / 뭘 누르면 되는지.
//
// 클래스 컴포넌트인 이유: getDerivedStateFromError · componentDidCatch는 훅 대응물이 아직
// 없다(React 19 기준). 외부 의존성 없이 이 파일 하나로 끝낸다.
import { Component, type ErrorInfo, type ReactNode } from "react";
import { RotateCw, TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui";

interface State {
  crashed: boolean;
}

export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { crashed: false };

  static getDerivedStateFromError(): State {
    return { crashed: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // 원문·스택은 개발자 몫으로 콘솔에만 남긴다. 화면에 실으면 영문 스택이 그대로 노출되는데,
    // 대표에게는 읽을 수 없는 글자일 뿐 아니라 무섭기만 하다.
    console.error("[ErrorBoundary] 렌더 중 예외:", error);
    console.error("[ErrorBoundary] 컴포넌트 스택:", info.componentStack);
  }

  render() {
    if (!this.state.crashed) return this.props.children;

    // 레이아웃은 Login·NoAccess와 같은 골격(고정 오버레이 + 360px 카드) — 사고 화면만
    // 낯선 디자인이면 "앱이 아닌 다른 무언가"로 보여 더 불안해진다.
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#05060a]/95 p-4">
        <div className="w-full max-w-[360px] rounded-2xl border border-line bg-panel p-7 text-center">
          <div className="mx-auto mb-3.5 flex h-11 w-11 items-center justify-center rounded-full bg-warn/15">
            <TriangleAlert className="h-5 w-5 text-warn" />
          </div>
          <div className="text-[15px] font-black">화면을 그리는 중 문제가 생겼어요</div>
          <p className="mt-2 text-[11.5px] leading-relaxed text-muted">
            회원·예약·결제 자료는 그대로 저장돼 있습니다. 이 화면만 잘못 그려진 것이라, 다시
            불러오면 대개 원래대로 돌아옵니다.
          </p>

          <Button className="mt-3.5 w-full" onClick={() => window.location.reload()}>
            <RotateCw className="h-4 w-4" /> 다시 불러오기
          </Button>

          {/* 반복 크래시(다시 불러와도 같은 자리에서 또 멈추는 경우)를 위한 줄. 이 제품에는
              연락할 관리자가 없으므로 "문의하세요"라고 쓰지 않는다 — 대신 원인 추적에 실제로
              쓸 수 있는, 대표가 지금 할 수 있는 일 하나만 남긴다. */}
          <p className="mt-3 text-[10.5px] leading-relaxed text-muted">
            다시 불러와도 같은 자리에서 멈춘다면, 직전에 어떤 화면에서 무엇을 하고 있었는지
            적어 두세요. 원인을 찾는 데 그 한 줄이 가장 큰 단서가 됩니다.
          </p>
        </div>
      </div>
    );
  }
}
