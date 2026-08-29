// 로그인 화면 — 목업 #login 카드 1:1 재현.
// 이메일·비밀번호 폼은 Firebase Auth 실로그인(P06) — loginEmail()이 signIn 후 /v1/me까지 세운다.
// 데모 버튼(로컬 개발용)은 X-Dev-Role/X-Dev-Uid 아이덴티티로 즉시 /v1/me를 조회해 세션을 세운다.
import { useState, type FormEvent } from "react";
import { FirebaseError } from "firebase/app";
import { sendPasswordResetEmail } from "firebase/auth";
import { BrandMark } from "@/components/BrandMark";
import { Button, Input } from "@/components/ui";
import { DEMO_OWNER, DEMO_TRAINER, useAuth } from "@/lib/auth";
import { auth } from "@/lib/firebase";

// Firebase Auth 오류 코드 → 한국어. invalid-credential은 이메일 열거 보호(기본 ON)로
// "없는 계정"과 "비번 틀림"을 구분해주지 않는다 — 메시지도 묶어서 안내한다.
const FB_ERROR_KO: Record<string, string> = {
  "auth/invalid-credential": "이메일 또는 비밀번호가 맞지 않아요",
  "auth/user-not-found": "이메일 또는 비밀번호가 맞지 않아요",
  "auth/wrong-password": "이메일 또는 비밀번호가 맞지 않아요",
  "auth/invalid-email": "이메일 형식이 올바르지 않아요",
  "auth/user-disabled": "비활성화된 계정이에요 — 관리자에게 문의하세요",
  "auth/too-many-requests": "로그인 시도가 너무 많았어요 — 잠시 후 다시 시도해주세요",
  "auth/network-request-failed": "네트워크 오류가 발생했어요 — 연결을 확인해주세요",
  "auth/operation-not-allowed": "이메일 로그인이 비활성화돼 있어요 — 관리자에게 문의하세요",
};

function toKoMessage(e: unknown): string {
  if (e instanceof FirebaseError) {
    return FB_ERROR_KO[e.code] ?? `로그인에 실패했어요 (${e.code})`;
  }
  return e instanceof Error ? e.message : "로그인에 실패했어요";
}

export function Login() {
  const { loginDev, loginEmail, logout, isLoading, error } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isPending, setIsPending] = useState(false);
  // Firebase 자격 오류(이 폼의 문제) — 백엔드 /v1/me 오류(컨텍스트 error)와 표시를 분리한다.
  const [fbError, setFbError] = useState<string | null>(null);
  const [resetSent, setResetSent] = useState(false);

  const busy = isPending || isLoading;

  // 비밀번호 재설정 — 계정 최초 발급(관리자가 임시 비번으로 만든 경우)과 분실 모두 이 경로다.
  // 계정 존재 여부는 알려주지 않는다(이메일 열거 방지): 성공·미존재 모두 같은 안내를 띄운다.
  async function onResetPassword() {
    if (busy) return;
    const target = email.trim();
    if (!target) {
      setFbError("재설정 메일을 받을 이메일을 먼저 입력해주세요");
      return;
    }
    setFbError(null);
    setIsPending(true);
    try {
      await sendPasswordResetEmail(auth, target);
      setResetSent(true);
    } catch (err) {
      // user-not-found도 성공처럼 처리 — 존재 여부 노출 방지.
      if (err instanceof FirebaseError && err.code === "auth/user-not-found") {
        setResetSent(true);
      } else {
        setFbError(toKoMessage(err));
      }
    } finally {
      setIsPending(false);
    }
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!email.trim() || !password) {
      setFbError("이메일과 비밀번호를 입력해주세요");
      return;
    }
    setFbError(null);
    setIsPending(true);
    try {
      // 성공 시 loginEmail이 /v1/me까지 세팅 → isAuthed 전환으로 이 화면이 닫힌다.
      await loginEmail(email.trim(), password);
    } catch (err) {
      setFbError(toKoMessage(err));
    } finally {
      setIsPending(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#05060a]/95 p-4">
      <div className="w-full max-w-[360px] rounded-2xl border border-line bg-panel p-7 text-center">
        {/* 브랜드 R 마크(P19) — 배경 타일 없이 획만. 다크 패널이라 ivory 톤(근거는 BrandMark 주석). */}
        <BrandMark size={56} tone="ivory" className="mx-auto mb-3.5" />
        <div className="text-[22px] font-black">
          RISE <span className="text-brand">CONDITIONING</span>
        </div>
        <div className="mb-[18px] mt-1 text-[11px] text-muted">
          라이즈 컨디셔닝 센터 어드민 · powered by PT데스크
        </div>

        <form onSubmit={onSubmit}>
          <div className="mb-2 text-left">
            <Input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="이메일"
              type="email"
              autoComplete="username"
              disabled={busy}
            />
          </div>
          <div className="mb-3.5 text-left">
            <Input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="비밀번호"
              type="password"
              autoComplete="current-password"
              disabled={busy}
            />
          </div>

          {fbError && <p className="mb-2.5 text-left text-[11px] text-danger">{fbError}</p>}
          {resetSent && (
            <p className="mb-2.5 text-left text-[11px] text-ok">
              재설정 메일을 보냈어요. 메일의 링크로 새 비밀번호를 정한 뒤 다시 로그인해주세요.
            </p>
          )}

          {/* 아이콘 없이 텍스트만 — 로그인 버튼은 화면에 하나뿐이라 아이콘이 구분에 기여하지
              않고, 문 모양 픽토그램이 한글 라벨 앞에 붙으면 기호처럼 읽힌다. */}
          <Button type="submit" className="w-full" disabled={busy}>
            {isPending ? "로그인 중…" : "이메일로 로그인"}
          </Button>

          <button
            type="button"
            onClick={() => void onResetPassword()}
            disabled={busy}
            className="mt-2.5 text-[11px] text-muted underline underline-offset-2 hover:text-ink disabled:opacity-50"
          >
            비밀번호를 잊으셨나요? / 처음 로그인이신가요?
          </button>
        </form>

        {/* 데모(X-Dev) 로그인은 개발 빌드에만 존재한다. 프로덕션 번들에 남겨두면 대표가 눌러
            실 Firebase 세션이 끊기고(loginDev의 signOut) 백엔드는 X-Dev를 무시하므로 401 화면에
            갇힌다 — 게다가 데모 아이덴티티가 localStorage에 남아 새로고침마다 재현된다.
            import.meta.env.DEV는 vite가 빌드 시 상수로 접어 트리셰이킹까지 된다. */}
        {import.meta.env.DEV && (
          <>
            <div className="my-3.5 flex items-center gap-2 text-[10.5px] text-muted">
              <span className="h-px flex-1 bg-line" />
              로컬 개발용
              <span className="h-px flex-1 bg-line" />
            </div>

            <Button
              variant="outline"
              className="w-full"
              disabled={busy}
              onClick={() => void loginDev(DEMO_OWNER)}
            >
              대표로 로그인 (데모 · {DEMO_OWNER.name})
            </Button>
            <Button
              variant="outline"
              className="mt-2 w-full"
              disabled={busy}
              onClick={() => void loginDev(DEMO_TRAINER)}
            >
              트레이너로 로그인 (데모 · {DEMO_TRAINER.name})
            </Button>
          </>
        )}

        {error && (
          <div className="mt-3 text-left">
            {/* /v1/me 실패 — 자격 문제가 아니라 서버 도달 문제인 경우가 대부분이다.
                개발 빌드에서만 로컬 백엔드 힌트를 덧붙인다(운영 사용자에게는 무의미한 안내). */}
            <p className="text-[11px] text-danger">
              로그인에 실패했어요: {error}
              {import.meta.env.DEV && " — 백엔드가 :8080에서 실행 중인지 확인하세요."}
            </p>
            {/* 탈출구. Firebase 로그인은 성공했는데 /v1/me가 실패하면(권한 미부여·서버 오류)
                세션이 살아 있는 채로 이 화면에 머무는데, 비밀번호를 다시 입력해도 같은 자리다.
                세션을 비워야 다른 계정으로 들어갈 수 있다. */}
            <button
              type="button"
              onClick={logout}
              className="mt-1.5 text-[11px] text-muted underline underline-offset-2 hover:text-ink"
            >
              세션 초기화하고 다른 계정으로 로그인
            </button>
          </div>
        )}

        <p className="mt-3.5 text-left text-[10.5px] leading-relaxed text-muted">
          로그인 시 역할(owner/trainer)에 따라 보이는 메뉴·데이터가 다릅니다. 매출·통계는 대표
          전용입니다.
          {import.meta.env.DEV && (
            <>
              <br />
              데모 버튼은 로컬 개발용(X-Dev 헤더)입니다 — 실계정은 이메일·비밀번호로 로그인하세요.
            </>
          )}
        </p>
      </div>
    </div>
  );
}
