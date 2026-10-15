// 인증 컨텍스트(P06) — Firebase 이메일 로그인(실계정)과 데모(X-Dev) 로그인이 공존한다.
// - Firebase 모드: signInWithEmailAndPassword → api.ts가 매 요청 ID 토큰을 Bearer로 첨부.
//   새로고침 세션 복원은 onAuthStateChanged 구독이 담당. 이 모드에선 identity(데모)가 항상
//   null이며 X-Dev 헤더도 싣지 않는다(충돌 방지 — 우선순위: Firebase > 데모).
// - 데모 모드: 로그인 화면 데모 버튼이 역할(owner/trainer)·uid를 정하면 api.ts가
//   X-Dev-Role · X-Dev-Uid 헤더로 실어 보낸다(로컬 개발용, API계약_v1.md 명시).
// 어느 모드든 진짜 역할·center_id는 /v1/me 응답이 단일 진실 — 로그인 직후 반드시 재확인한다.
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { signInWithEmailAndPassword, signOut, onAuthStateChanged } from "firebase/auth";
import { useQueryClient } from "@tanstack/react-query";
import { api } from "./api";
import { clearBodyPhotoBlobs } from "./bodyPhotoBlob";
import { auth } from "./firebase";
import type { Me, Role } from "./types";

const STORAGE_KEY = "rise-admin-dev-identity";

export interface DevIdentity {
  role: Role;
  uid: string;
  name: string;
}

// 로그인 화면·헤더 역할전환 pill이 공유하는 데모 아이덴티티.
// v1.4: 백엔드 DEV_SEED 데모 데이터의 스태프 uid(owner1 박관장·t1 정혜린)와 일치시켰다 —
// uid가 어긋나면 트레이너 스코프(담당 회원·본인 일정·본인 정산)가 전부 빈 화면이 된다.
export const DEMO_OWNER: DevIdentity = { role: "owner", uid: "owner1", name: "박관장" };
export const DEMO_TRAINER: DevIdentity = { role: "trainer", uid: "t1", name: "정혜린" };

// 백엔드 DEV_SEED 스태프 uid 전체(owner1 박관장 · t1 정혜린 · t2 김태오, store/seed.go).
// uid를 맞추기 전(구버전)에 저장된 아이덴티티가 복원되면 스코프 GET이 전부 빈 화면이 되므로,
// 이 밖의 uid는 복원 시 폐기하고 로그인 화면으로 보낸다.
const VALID_DEMO_UIDS = new Set(["owner1", "t1", "t2"]);

interface AuthContextValue {
  me: Me | null;
  /** 데모(X-Dev) 모드일 때만 non-null — Firebase 로그인 상태에선 항상 null(역할전환 pill 표시 조건). */
  identity: DevIdentity | null;
  /** Firebase 로그인 계정 이메일(헤더 표시용) — 데모 모드·로그아웃 상태에선 null. */
  fbEmail: string | null;
  isLoading: boolean;
  error: string | null;
  isAuthed: boolean;
  loginDev: (identity: DevIdentity) => Promise<void>;
  /** Firebase 이메일 로그인 — 자격 오류는 FirebaseError를 그대로 던진다(화면에서 코드→한국어 매핑). */
  loginEmail: (email: string, password: string) => Promise<void>;
  /** 표시 정보(me.name 등)만 다시 읽는다 — 실패해도 세션을 유지한다. */
  refreshMe: () => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function readStoredIdentity(): DevIdentity | null {
  // 프로덕션 빌드는 저장된 데모 신원을 **복원하지 않고 지운다**. 데모 버튼이 잠시 배포판에
  // 노출된 적이 있어(P08) 이미 눌러본 브라우저에는 값이 남아 있는데, 그대로 복원하면 매 부팅마다
  // X-Dev 헤더로 /v1/me를 때리고 프로덕션 백엔드는 이를 무시하므로 401 → 로그인 화면 → 무한 반복이
  // 된다. 데모 버튼도 이제 없으니 사용자가 스스로 빠져나올 방법이 없다. 여기서 끊는다.
  if (!import.meta.env.DEV) {
    localStorage.removeItem(STORAGE_KEY);
    return null;
  }
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as DevIdentity;
    if (typeof parsed?.uid !== "string" || !VALID_DEMO_UIDS.has(parsed.uid)) {
      // 구버전 데모 uid(시드와 어긋난 저장값) — 폐기하고 로그인 화면으로.
      localStorage.removeItem(STORAGE_KEY);
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient();
  const [identity, setIdentity] = useState<DevIdentity | null>(null);
  const [fbEmail, setFbEmail] = useState<string | null>(null);
  const [me, setMe] = useState<Me | null>(null);
  // true로 시작: 첫 onAuthStateChanged(세션 복원 판정)까지 로그인 화면 깜빡임을 막는다.
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // 리스너 콜백은 [] 의존 effect 안에서 살아가므로 최신 identity를 ref로 본다(stale closure 방지).
  const identityRef = useRef<DevIdentity | null>(null);
  // loginEmail() 진행 중 표시 — signIn 직후 리스너가 fetchMe를 중복 호출하지 않게 한다
  // (성공 시 fetchMe는 loginEmail 본인이 호출). 최악의 어긋남도 GET /v1/me 1회 중복으로 수렴.
  const explicitLoginRef = useRef(false);
  // 첫 콜백(부팅 복원)과 이후 상태 변화(외부 로그아웃 등)를 구분한다.
  const bootedRef = useRef(false);
  // 직전 콜백의 Firebase uid — 다른 탭이 **다른 계정으로 곧장** 로그인하면(signOut 없이) 이 탭은
  // null을 거치지 않고 새 사용자를 받는다. 그 전환을 알아보는 데만 쓴다(P74).
  const lastUidRef = useRef<string | null>(null);
  // 401 인터셉터가 부를 최신 logout — 등록은 마운트 1회뿐이라 콜백을 ref로 우회한다
  // (logout을 의존성에 넣으면 매 렌더 재등록되고, 넣지 않으면 stale closure가 된다).
  const logoutRef = useRef<() => void>(() => {});

  // 데모 identity의 단일 세터 — React 상태 + 리스너용 ref + api 모듈 헤더 변수를 항상 함께 맞춘다.
  const applyIdentity = useCallback((id: DevIdentity | null) => {
    identityRef.current = id;
    setIdentity(id);
    api.setDevIdentity(id?.role ?? null, id?.uid ?? null);
  }, []);

  // /v1/me 조회 — 호출 전에 인증 경로(Firebase currentUser 또는 데모 identity)가 준비돼 있어야
  // 한다. 실패는 던지지 않고 error 상태로 흘린다(로그인 화면이 그대로 표시).
  const fetchMe = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const result = await api.me();
      setMe(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setMe(null);
    } finally {
      setIsLoading(false);
    }
  }, []);

  // refreshMe — /v1/me를 다시 읽되 **실패해도 세션을 내리지 않는다**(v2.2).
  //
  // fetchMe와 나뉘는 이유: fetchMe는 로그인 경로라 실패 시 me=null로 내려 로그인 화면을 띄우는
  // 게 맞다. 반면 이건 이미 들어와 있는 사용자의 표시 정보만 새로 고치는 것이라, 일시적
  // 네트워크 오류로 화면 밖으로 튕겨내면 잃는 게 훨씬 크다 — 옛 값을 그대로 두는 편이 낫다.
  //
  // 필요해진 계기: 헤더 이름의 1순위가 me.name이 되면서, 설정에서 **자기 이름을 바꿔도**
  // staff 캐시 무효화가 헤더에 닿지 않아 새로고침 전까지 옛 이름이 남았다(종전엔 헤더가
  // staff 목록을 조인했으므로 무효화만으로 갱신됐다 — 이 변경이 만든 회귀다).
  const refreshMe = useCallback(async () => {
    try {
      setMe(await api.me());
    } catch {
      // 표시 정보 갱신 실패는 조용히 넘긴다 — 기존 me를 유지한다.
    }
  }, []);

  // 401 → 세션 정리(v2.0). 퇴사 처리를 받으면 서버가 UserIndex를 강등하고 Firebase 계정을
  // 잠그지만, 인터셉터가 없던 동안엔 logout()이 호출되는 곳이 0곳이라 셸이 계속 렌더되고
  // 패널만 빨간 에러가 됐다. api.ts는 React를 모르므로 여기서 콜백을 꽂는다.
  // (403은 넘기지 않는다 — 권한 밖 기능을 눌렀을 뿐인 정상 상황과 구분되지 않는다. api.ts 참고.)
  //
  // logout()은 멱등이고 요청을 만들지 않으므로 401이 연달아 와도 루프가 생기지 않는다.
  // 아래 onAuthStateChanged 구독보다 **먼저** 선언해 첫 /v1/me보다 등록이 앞서게 한다.
  useEffect(() => {
    api.setUnauthorizedHandler(() => logoutRef.current());
    return () => api.setUnauthorizedHandler(null);
  }, []);

  // Firebase 세션 구독 — (1) 새로고침 시 세션 복원(Firebase 우선, 없으면 저장된 데모 폴백),
  // (2) 부팅 후 외부 요인(다른 탭 signOut·토큰 무효화)으로 세션이 끊기면 화면 세션도 정리.
  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (user) => {
      const isBoot = !bootedRef.current;
      bootedRef.current = true;
      const prevUid = lastUidRef.current;
      lastUidRef.current = user?.uid ?? null;
      setFbEmail(user?.email ?? null);

      if (user) {
        // 계정이 **바뀌었다**(다른 탭에서 다른 계정으로 바로 로그인 — Firebase가 탭 사이에 동기화한다).
        // 아래 로그아웃 정리를 거치지 않으므로 여기서 같은 정리를 한다: 쿼리 키에 uid·센터가 없어
        // 이전 계정의 목록(staleTime 60초)과 체형사진 blob이 새 계정 화면에 그대로 보인다. me도 내려
        // 이전 계정의 역할로 그린 화면이 새 계정 데이터와 섞이지 않게 한다(fetchMe가 로딩부터 다시).
        if (prevUid && prevUid !== user.uid) {
          setMe(null);
          qc.clear();
          clearBodyPhotoBlobs();
        }
        // Firebase 로그인 확인 — 데모 identity는 해제(우선순위: Firebase > 데모).
        applyIdentity(null);
        // 리스너 주도 케이스(새로고침 복원·다른 탭 로그인)만 여기서 조회 —
        // loginEmail 경로는 본인이 fetchMe를 호출한다.
        if (!explicitLoginRef.current) void fetchMe();
        return;
      }

      if (isBoot) {
        // 부팅 시 Firebase 세션 없음 → 저장된 데모 identity로 자동 재로그인(기존 동작).
        const stored = readStoredIdentity();
        if (stored) {
          applyIdentity(stored);
          void fetchMe();
        } else {
          setIsLoading(false); // 로그인 화면으로.
        }
        return;
      }

      // 부팅 후 Firebase 세션 소멸. 우리 logout()/loginDev()가 이미 정리한 뒤에도 오지만(멱등),
      // 외부 요인일 수 있으니 데모 모드가 아니고 로그인 진행 중도 아니면 세션을 정리한다.
      if (!identityRef.current && !explicitLoginRef.current) {
        setMe(null);
        setError(null);
        setIsLoading(false);
        qc.clear();
        clearBodyPhotoBlobs();
      }
    });
    return unsub;
  }, [applyIdentity, fetchMe, qc]);

  const loginDev = useCallback(
    async (id: DevIdentity) => {
      // 데모 identity를 먼저 확정 — 아래 signOut이 깨우는 리스너가 "외부 로그아웃 정리"로
      // 오인해 방금 세운 데모 세션을 지우지 않게 한다(identityRef 선점).
      localStorage.setItem(STORAGE_KEY, JSON.stringify(id));
      applyIdentity(id);
      // Firebase 세션이 남아 있으면 종료 — api.req()가 Bearer를 우선하므로 X-Dev 데모가 묻힌다.
      // (역할전환 pill은 Firebase 모드에서 숨기지만, 방어적으로 여기서도 보장한다.)
      if (auth.currentUser) await signOut(auth);
      // 역할이 바뀌면 서버 스코프(담당 회원·본인 정산 등)도 바뀌므로 캐시를 통째로 비워
      // 이전 역할 데이터가 화면에 잔류하는 걸 막는다(권한 경계 데모의 핵심).
      qc.clear();
      clearBodyPhotoBlobs();
      await fetchMe();
    },
    [applyIdentity, fetchMe, qc],
  );

  const loginEmail = useCallback(
    async (email: string, password: string) => {
      explicitLoginRef.current = true;
      try {
        // 자격 오류(auth/invalid-credential 등)는 여기서 throw → 로그인 화면이 한국어로 매핑.
        await signInWithEmailAndPassword(auth, email, password);
        // 실계정 모드 진입: 데모 흔적을 지운다 — 남겨두면 먼 훗날 Firebase 세션 만료 시
        // 저장된 데모로 소리 없이 자동 로그인되는 놀람이 생긴다(우선순위 Firebase > 데모의 연장).
        localStorage.removeItem(STORAGE_KEY);
        applyIdentity(null);
        qc.clear();
        clearBodyPhotoBlobs();
        // 이제 api.req()가 currentUser의 ID 토큰을 Bearer로 첨부한다. /v1/me 실패는
        // error 상태로 흘러 로그인 화면에 표시된다(Firebase 세션은 유지 — 재시도 가능).
        await fetchMe();
      } finally {
        explicitLoginRef.current = false;
      }
    },
    [applyIdentity, fetchMe, qc],
  );

  const logout = useCallback(() => {
    // Firebase 세션 종료(있을 때만) — 로컬 정리는 기다리지 않고 즉시 수행한다.
    // signOut이 깨우는 리스너의 후속 정리는 멱등이라 이중 실행돼도 무해.
    if (auth.currentUser) void signOut(auth);
    localStorage.removeItem(STORAGE_KEY);
    applyIdentity(null);
    setFbEmail(null);
    setMe(null);
    setError(null);
    // 세션이 바뀌면 React Query 캐시(qc.clear)만으로는 부족하다 — 체형사진 blob은 모듈 전역 Map에
    // 따로 산다(bodyPhotoBlob.ts). 로그아웃은 페이지 리로드가 아니라 SPA 상태 전환이라, 비우지
    // 않으면 데스크 공용 브라우저에서 다음 사람 세션까지 이전 사람이 본 민감 사진 바이너리가
    // 탭 메모리에 남는다(P74 — 함수는 그 목적으로 이미 있었는데 호출부가 0곳이었다).
    qc.clear();
    clearBodyPhotoBlobs();
  }, [applyIdentity, qc]);
  // 렌더 본문에서 갱신 — 위 마운트 1회 effect가 실행될 시점엔 이미 최신 함수가 들어 있다.
  logoutRef.current = logout;

  const value = useMemo<AuthContextValue>(
    () => ({
      me,
      identity,
      fbEmail,
      isLoading,
      error,
      isAuthed: !!me,
      loginDev,
      loginEmail,
      refreshMe,
      logout,
    }),
    [me, identity, fbEmail, isLoading, error, loginDev, loginEmail, refreshMe, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth()는 AuthProvider 내부에서만 호출할 수 있습니다.");
  return ctx;
}
