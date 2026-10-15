// 초대 계정의 **최초 비밀번호 안내**(계약 v2.36, P71).
//
// ## 왜 생겼나
//
// 종전 설계는 "서버가 아무도 모르는 난수 비밀번호를 걸고, 어드민 프론트가 곧바로
// sendPasswordResetEmail을 보낸다"였다. 트레이너 초대(Settings.tsx)는 그 규약을 지켰는데
// **센터 생성(Centers.tsx)에는 그 호출이 아예 없었다** — 새 센터 대표는 메일도 못 받고
// 비밀번호도 모르는 계정만 받았다. 로그인할 방법이 0인 계정이다.
//
// 메일 경로만으로는 부족하다는 것도 함께 드러났다: 스팸함으로 가거나, 도메인 메일이 막힌
// 헬스장이거나, 오타 주소면 초대가 통째로 멈추는데 대표가 손쓸 수단이 없다.
//
// 그래서 서버가 **관리자가 말해 줄 수 있는 값**으로 계정을 만들고 그 값을 생성 응답에 담는다.
// 메일은 그대로 보낸다 — 이 화면은 메일을 **대체하는 게 아니라 무너졌을 때의 경로**다.
//
// ## 이 컴포넌트가 지키는 두 가지
//
// ① **빈 값에 기본 비밀번호를 적지 않는다.** 서버는 이번 요청으로 계정을 새로 만들었을 때만
//    initial_password를 채운다. 재초대·재고용이면 그 사람이 이미 정한 비밀번호가 살아 있는데,
//    여기에 "123456"을 적으면 관리자가 틀린 값을 불러 주고 상대는 원인도 모른 채 실패한다.
// ② **바꾸라고 말한다.** 이 값은 저장소에 적힌 상수라 아는 사람이 있을 수 있다. 안내 없이
//    비밀번호만 띄우면 그대로 쓰는 계정이 남는다.

import { useState } from "react";
import { Check, Copy, KeyRound } from "lucide-react";

export function InitialPasswordNotice({
  email,
  password,
  who,
}: {
  email: string;
  /** 서버가 새 계정을 만들었을 때만 채워진다. 비어 있으면 이 컴포넌트는 **다른 문장**을 그린다. */
  password?: string;
  /** "대표" / "트레이너" — 문장에 들어가는 호칭. */
  who: string;
}) {
  const [copied, setCopied] = useState(false);

  // 계정이 이미 있던 경우 — 비밀번호를 아는 사람은 본인뿐이다. 없는 값을 지어내지 않는다.
  if (!password) {
    return (
      <div className="rounded-[10px] border border-line bg-panel-2 px-3 py-2.5 text-[12.5px] leading-relaxed">
        <p className="text-ink">
          <b>{email}</b> 계정은 이미 있어서 그대로 연결했어요.
        </p>
        <p className="mt-1 text-muted">
          그래서 이 {who}는 <b className="text-ink">쓰던 비밀번호</b>로 로그인합니다. 기억나지 않으면
          로그인 화면의 <b className="text-ink">"비밀번호를 잊으셨나요"</b>를 누르면 됩니다.
        </p>
      </div>
    );
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(password!);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // 클립보드 권한이 없는 브라우저 — 값은 화면에 그대로 떠 있으므로 실패해도 잃는 게 없다.
      // 실패를 에러로 띄우면 "복사만 실패했는데 초대가 실패한 줄" 아는 오해를 만든다.
    }
  }

  return (
    <div className="rounded-[10px] border border-brand/30 bg-brand/10 px-3 py-2.5">
      <p className="flex items-center gap-1.5 text-[12.5px] font-bold text-ink">
        <KeyRound className="h-3.5 w-3.5 shrink-0" />첫 로그인 정보 — {who}에게 전달하세요
      </p>
      <dl className="mt-2 space-y-1.5 text-[12.5px]">
        <div className="flex items-baseline gap-2">
          <dt className="w-14 shrink-0 text-muted">이메일</dt>
          <dd className="break-all font-mono text-ink">{email}</dd>
        </div>
        <div className="flex items-baseline gap-2">
          <dt className="w-14 shrink-0 text-muted">비밀번호</dt>
          <dd className="flex items-center gap-2">
            <span className="font-mono text-[14px] font-bold tracking-wider text-ink">{password}</span>
            <button
              type="button"
              onClick={() => void copy()}
              className="inline-flex items-center gap-1 rounded-[7px] border border-line px-1.5 py-0.5 text-[11px] text-muted transition hover:bg-panel hover:text-ink"
            >
              {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
              {copied ? "복사됨" : "복사"}
            </button>
          </dd>
        </div>
      </dl>
      <p className="mt-2 text-[11.5px] leading-relaxed text-warn">
        로그인한 뒤 <b>비밀번호를 꼭 바꾸도록</b> 안내하세요. 모든 센터가 같은 기본 비밀번호로
        시작합니다.
      </p>
    </div>
  );
}
