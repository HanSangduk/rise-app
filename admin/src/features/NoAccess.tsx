// 권한 없음 화면 — 로그인은 됐지만 어드민 역할(owner/trainer)이 아닌 계정이 도달한다.
// 백엔드는 UserIndex가 없는 Firebase 계정을 가입 부트스트랩 목적으로 기본 role=member로
// 통과시키므로(backend/internal/api/auth.go), 어드민 셸을 isAuthed만으로 열면 안 된다:
// 대시보드·예약·회원 탭은 보이는데 설정·직원 탭은 없고 패널마다 "권한이 없어요"가 뜨는
// 반쪽 화면이 된다. 셸에 들여보내는 대신 여기서 상태와 다음 행동만 알려주고 끊는다.
// 레이아웃은 Login 카드와 같은 골격(고정 오버레이 + 360px 카드)이라 로그아웃 후 전환이 매끄럽다.
import { LogOut, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui";
import { useAuth } from "@/lib/auth";

export function NoAccess() {
  const { me, identity, fbEmail, logout } = useAuth();
  // 어느 계정으로 들어와 있는지 먼저 알려준다 — 회사 계정과 개인 계정을 섞어 쓰다 도달하는
  // 경우가 많아, 계정 표시가 없으면 "왜 안 되는지" 자체를 알 수 없다.
  const account = fbEmail ?? identity?.name ?? me?.uid;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#05060a]/95 p-4">
      <div className="w-full max-w-[360px] rounded-2xl border border-line bg-panel p-7 text-center">
        <div className="mx-auto mb-3.5 flex h-11 w-11 items-center justify-center rounded-full bg-warn/15">
          <ShieldAlert className="h-5 w-5 text-warn" />
        </div>
        <div className="text-[15px] font-black">어드민 접근 권한이 없어요</div>
        <p className="mt-2 text-[11.5px] leading-relaxed text-muted">
          {account && (
            <>
              <b className="text-ink">{account}</b> 계정에는{" "}
            </>
          )}
          라이즈 어드민을 사용할 수 있는 권한(대표·트레이너)이 없습니다.
        </p>

        <div className="mt-3.5 rounded-[10px] border border-line bg-panel-2 p-3 text-left text-[11px] leading-relaxed text-muted">
          <p>
            <b className="text-ink">회원이신가요?</b> 라이즈 회원 앱으로 로그인해주세요. 앱에서
            번호 인증을 하면 센터에 자동으로 연결되고, 매칭되지 않으면 가입 요청이 대표에게
            전달됩니다.
          </p>
          <p className="mt-2">
            <b className="text-ink">트레이너이신가요?</b> 센터 대표에게 초대를 요청해주세요. 초대
            메일로 비밀번호를 설정한 계정이라야 어드민에 들어올 수 있습니다.
          </p>
        </div>

        <Button className="mt-3.5 w-full" onClick={logout}>
          <LogOut className="h-4 w-4" /> 로그아웃 · 다른 계정으로 로그인
        </Button>
      </div>
    </div>
  );
}
