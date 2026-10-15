// 어드민 셸 — 인증 게이트 → 사이드바 레이아웃(반응형: <880px 상단 가로 네비) → 역할별 메뉴.
// 라우팅은 wodshot web과 동일하게 상태 기반 탭(딥링크 불필요 규모 — TanStack Router 승격은 보류).
import { lazy, Suspense, useEffect, useMemo, useState } from "react";
import {
  BarChart3,
  CalendarDays,
  Camera,
  ClipboardList,
  IdCard,
  LayoutDashboard,
  LogOut,
  Settings as SettingsIcon,
  Users,
  Building2,
  type LucideIcon,
} from "lucide-react";
import { BrandMark } from "@/components/BrandMark";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { Spinner } from "@/components/ui";
import { cn } from "@/lib/cn";
import { DEMO_OWNER, DEMO_TRAINER, useAuth } from "@/lib/auth";
import { firstNonEmpty } from "@/lib/format";
import { useCenter, useJoinRequests, useStaff } from "@/lib/queries";
import { centerDisplayName, isJoinPending } from "@/lib/types";
import { Login } from "@/features/Login";
import { NoAccess } from "@/features/NoAccess";

// 기능 화면은 **지연 로드**한다(P74). 종전엔 9개 화면이 전부 정적 import라 로그인 화면부터 전 화면
// 코드(8,600줄+)를 받았고, 트레이너는 서버가 403으로 막아 **절대 열 수 없는** 설정·매출 화면까지
// 내려받았다(빌드 경고: 500kB 초과 청크). 렌더 분기(`section === …`)는 런타임 조건일 뿐 번들을
// 나누지 않는다 — import를 동적으로 바꿔야 Vite가 화면별 청크를 만든다. 로그인·권한 화면은 첫
// 화면이라 정적으로 둔다. named export를 default로 감싸는 이유: React.lazy는 default만 받는다.
const Dashboard = lazy(() => import("@/features/Dashboard").then((m) => ({ default: m.Dashboard })));
const Schedule = lazy(() => import("@/features/Schedule").then((m) => ({ default: m.Schedule })));
const Members = lazy(() => import("@/features/Members").then((m) => ({ default: m.Members })));
const Sales = lazy(() => import("@/features/Sales").then((m) => ({ default: m.Sales })));
const Homework = lazy(() => import("@/features/Homework").then((m) => ({ default: m.Homework })));
const BodyPhotos = lazy(() => import("@/features/BodyPhotos").then((m) => ({ default: m.BodyPhotos })));
const MyProfile = lazy(() => import("@/features/MyProfile").then((m) => ({ default: m.MyProfile })));
const Settings = lazy(() => import("@/features/Settings").then((m) => ({ default: m.Settings })));
const Centers = lazy(() => import("@/features/Centers").then((m) => ({ default: m.Centers })));

type Section = "dash" | "cal" | "members" | "sales" | "hw" | "body" | "me" | "set" | "centers";

// ownerOnly — 서버가 owner 전용인 화면(매출·설정). trainerOnly — 대표에겐 중복이라 감추는 화면:
// "내 프로필·휴무"는 트레이너가 자기 것을 고치는 자리인데(서버는 본인에게 허용 — P58 B3), 대표는
// 설정 탭의 직원 표에서 자기 행을 포함해 누구의 것이든 고치므로 같은 문을 두 개 두지 않는다.
const NAV: {
  id: Section;
  label: string;
  icon: LucideIcon;
  ownerOnly?: boolean;
  trainerOnly?: boolean;
}[] = [
  { id: "dash", label: "대시보드", icon: LayoutDashboard },
  { id: "cal", label: "예약 (3팀/시간)", icon: CalendarDays },
  { id: "members", label: "회원 관리", icon: Users },
  { id: "sales", label: "매출·통계", icon: BarChart3, ownerOnly: true },
  { id: "hw", label: "Home Work", icon: ClipboardList },
  { id: "body", label: "체형 분석", icon: Camera },
  { id: "me", label: "내 프로필·휴무", icon: IdCard, trainerOnly: true },
  { id: "set", label: "설정·직원", icon: SettingsIcon, ownerOnly: true },
];

// superadmin 셸 — **완전히 다른 네비**다. 서버가 superadmin에게 `/v1/admin/*`과 `/v1/me` 외
// 전부를 403으로 막으므로(auth.go superadminAllowedPath), 위 NAV를 필터해서 보여 주면 어느
// 탭을 눌러도 403 화면만 나온다. "눌러보고 403을 받는 UI를 만들지 않는다"는 규약이 여기서는
// 화면 단위가 아니라 **셸 단위**로 적용된다.
const SUPERADMIN_NAV: { id: Section; label: string; icon: LucideIcon }[] = [
  { id: "centers", label: "센터 관리", icon: Building2 },
];

const TITLES: Record<Section, string> = {
  dash: "대시보드",
  cal: "예약",
  members: "회원 관리",
  sales: "매출·통계",
  hw: "Home Work",
  body: "체형 분석",
  me: "내 프로필·휴무",
  set: "설정·직원",
  centers: "센터 관리",
};

// 셸 전체를 에러 경계로 감싼다 — 경계는 자기 **자식**의 렌더 예외만 잡으므로, 본체를
// AdminShell로 내리고 여기서 감싸는 형태여야 로그인·권한 화면부터 모든 기능 탭까지 다 덮인다.
// (한 단계 위의 AuthProvider·QueryClientProvider는 main.tsx 소관이라 이 경계 밖에 있다.)
export default function App() {
  return (
    <ErrorBoundary>
      <AdminShell />
    </ErrorBoundary>
  );
}

function AdminShell() {
  // fbEmail은 헤더 표시 이름의 폴백으로만 쓰여 HeaderIdentity가 직접 읽는다.
  const { me, identity, isLoading, isAuthed, loginDev, logout } = useAuth();
  const [section, setSection] = useState<Section>("dash");
  // 대시보드 "해야 할 일"에서 회원 이름 클릭 → 회원 관리 탭 + 해당 회원 상세(v1.4 UX 여정 마감).
  // 섹션 전환 시 Members가 리마운트되므로 초기 선택값 prop으로 충분하다(CustomEvent 불필요).
  const [memberFocusId, setMemberFocusId] = useState<string | null>(null);
  // 대시보드 "가입 요청 대기"의 신청자 이름 클릭 → 회원 관리 탭 + 상단 큐의 그 행 강조(P69).
  // memberFocusId와 같은 리마운트 규약, 같은 자리에서 함께 지운다(openSection).
  const [joinFocusId, setJoinFocusId] = useState<string | null>(null);

  const isOwner = me?.role === "owner";
  // superadmin — 센터를 만드는 사람. 센터 소속이 없어(center_id: "") 일상 운영 화면은 전부
  // 403이므로 셸 자체를 가른다.
  const isSuperadmin = me?.role === "superadmin";
  // 어드민을 쓸 수 있는 역할은 스태프(대표·트레이너)뿐 — role=member는 셸에 들이지 않는다.
  const isStaff = me?.role === "owner" || me?.role === "trainer";
  const nav = useMemo(
    () =>
      isSuperadmin
        ? SUPERADMIN_NAV
        : NAV.filter((n) => (!n.ownerOnly || isOwner) && (!n.trainerOnly || !isOwner)),
    // isSuperadmin도 deps에 있어야 한다. AdminShell은 로그인 화면 단계에서 이미 마운트돼
    // 첫 렌더(me=null)에 트레이너용 NAV로 굳는데, 이후 me가 superadmin으로 확정돼도 isOwner는
    // 그대로 false라 재계산되지 않았다 — superadmin이 "센터 관리" 없는 트레이너 메뉴를 보고
    // 대시보드의 403("관리 평면만 사용할 수 있어요")을 첫 화면으로 만나는 원인이었다.
    [isOwner, isSuperadmin],
  );

  function openMember(memberId: string) {
    setMemberFocusId(memberId);
    setJoinFocusId(null);
    setSection("members");
  }

  function openJoinRequest(requestId: string) {
    setMemberFocusId(null);
    setJoinFocusId(requestId);
    setSection("members");
  }

  // 탭 이동(네비 클릭·대시보드 온보딩/할 일 링크 공용) — 대시보드발 회원·가입 요청 포커스를 지운다.
  // 남겨두면 다음 회원 관리 진입 시 이전 포커스가 되살아나는 잔상이 생긴다.
  function openSection(id: Section) {
    setMemberFocusId(null);
    setJoinFocusId(null);
    setSection(id);
  }

  // 역할이 바뀌어 지금 역할에 없는 화면(트레이너→매출·설정, 대표→내 프로필)에 남아있으면
  // 대시보드로 되돌린다(목업 setRole 동작과 동일).
  // "dash"가 아니라 nav의 첫 항목으로 보낸다 — superadmin 네비에는 dash가 없어서 "dash"로
  // 되돌리면 대시보드가 렌더돼 센터 API를 때리고 403이 첫 화면이 된다.
  useEffect(() => {
    if (!nav.some((n) => n.id === section)) setSection(nav[0].id);
  }, [nav, section]);

  if (!isAuthed) {
    return isLoading ? (
      <div className="flex min-h-screen items-center justify-center bg-bg">
        <Spinner label="로그인 확인 중…" />
      </div>
    ) : (
      <Login />
    );
  }

  // 역할 게이트 — 인증(isAuthed)과 권한은 별개다. 백엔드가 UserIndex 없는 계정을 role=member로
  // 통과시키므로(가입 부트스트랩) 여기서 걸러야 "로그인은 됐는데 전부 고장난 화면"이 안 뜬다.
  if (!isStaff && !isSuperadmin) return <NoAccess />;

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      {/* 사이드바(< 880px: 상단 가로 스크롤 네비로 전환) */}
      <aside className="flex shrink-0 gap-1 overflow-x-auto border-b border-line bg-[#0a0b10] p-2 md:w-[212px] md:flex-col md:overflow-visible md:border-b-0 md:border-r md:p-2.5">
        <div className="hidden px-2 pb-4 md:block">
          {/* R 마크(P19) — 로그인 화면과 같은 마크를 22px로. 사이드바도 다크(#0a0b10)라 ivory 톤.
              모바일(<880px) 가로 네비에서는 브랜드 블록 전체가 원래 숨어 마크도 함께 빠진다. */}
          <div className="flex items-center gap-2 text-lg font-black tracking-tight">
            <BrandMark size={22} tone="ivory" className="shrink-0" />
            <span>
              RISE <span className="text-brand">어드민</span>
            </span>
          </div>
          {/* [P55] 하드코딩된 상호("라이즈 컨디셔닝 센터 (강남)")를 걷어냈다 — 서버 값이 있으면
              그것을, 없으면 종전과 같은 문자열을 쓴다(types.ts centerDisplayName). */}
          <div className="text-[10.5px] text-muted">
            <CenterName />
          </div>
        </div>
        {nav.map((n) => (
          <button
            key={n.id}
            onClick={() => openSection(n.id)}
            className={cn(
              "flex shrink-0 items-center gap-2 whitespace-nowrap rounded-[9px] px-2.5 py-2 text-left text-[13.5px] transition",
              section === n.id
                ? "bg-brand/15 font-extrabold text-brand"
                : "text-muted hover:bg-panel-2 hover:text-ink",
            )}
          >
            <n.icon className="h-4 w-4 shrink-0" />
            <span>{n.label}</span>
            {/* 회원 관리에 앱 가입 요청 대기 건수(P69, 대표만). 큐가 회원 관리 상단에 있다는 것을
                네비가 먼저 말한다 — 라벨 어디에도 "가입/요청"이 없어 대표가 큐를 못 찾았다. */}
            {n.id === "members" && isOwner && !isSuperadmin && <NavJoinBadge />}
          </button>
        ))}
      </aside>

      {/* 본문 */}
      <main className="min-w-0 flex-1">
        <header className="flex flex-wrap items-center justify-between gap-2.5 border-b border-line bg-panel px-5 py-2.5">
          <div className="text-[13px] text-muted">
            <CenterName /> · <b className="text-ink">{TITLES[section]}</b>
          </div>
          <div className="flex items-center gap-2.5">
            {/* 역할전환 pill — 데모(X-Dev) 모드 전용. 이중 게이트다: 빌드 게이트(import.meta.env.DEV)로
                프로덕션 번들에서 코드 자체를 들어내고, 런타임 게이트(identity)로 개발 빌드에서도
                실계정 로그인 시에는 숨긴다. 실계정의 역할은 서버 UserIndex 소관이라 클라이언트에서
                바꿔치기할 수 없다. */}
            {import.meta.env.DEV && identity && (
              <div className="flex items-center gap-0.5 rounded-full border border-line bg-panel-2 p-0.5">
                <button
                  onClick={() => void loginDev(DEMO_OWNER)}
                  className={cn(
                    "rounded-full px-3 py-1 text-[11.5px] font-extrabold transition",
                    isOwner ? "bg-brand-2 text-white" : "text-muted hover:text-ink",
                  )}
                >
                  대표 {DEMO_OWNER.name}
                </button>
                <button
                  onClick={() => void loginDev(DEMO_TRAINER)}
                  className={cn(
                    "rounded-full px-3 py-1 text-[11.5px] font-extrabold transition",
                    !isOwner ? "bg-brand-2 text-white" : "text-muted hover:text-ink",
                  )}
                >
                  트레이너 {DEMO_TRAINER.name}
                </button>
              </div>
            )}
            <HeaderIdentity />
            <button
              onClick={logout}
              className="flex items-center gap-1 rounded-full border border-line bg-panel-2 px-2.5 py-1 text-[11px] text-muted transition hover:text-ink"
            >
              <LogOut className="h-3 w-3" /> 로그아웃
            </button>
          </div>
        </header>
        <div className="max-w-[1200px] p-4 md:p-5">
          {/* 청크가 아직 안 왔을 때만 스피너 — 이미 받은 화면은 즉시 그려진다(Suspense는 첫 로드에만 걸린다). */}
          <Suspense fallback={<Spinner />}>
            {section === "dash" && (
              <Dashboard
                onOpenMember={openMember}
                onOpenMembers={() => openSection("members")}
                // 가입 요청 큐는 대표 전용(회원 관리 상단, owner 게이트) — 트레이너에겐 콜백을 주지 않는다.
                onOpenJoinRequest={isOwner ? openJoinRequest : undefined}
                // 설정 탭은 대표 전용이라 트레이너에겐 콜백 자체를 주지 않는다 — 화면에서
                // 눌러봐야 되돌려지는 데드 링크를 만들지 않는다(대시보드도 owner 게이트를 건다).
                onOpenSettings={isOwner ? () => openSection("set") : undefined}
              />
            )}
            {section === "cal" && <Schedule />}
            {section === "members" && (
              <Members focusMemberId={memberFocusId} focusJoinRequestId={joinFocusId} />
            )}
            {section === "sales" && isOwner && <Sales />}
            {section === "hw" && <Homework />}
            {section === "body" && <BodyPhotos />}
            {section === "me" && !isOwner && <MyProfile />}
            {section === "set" && isOwner && <Settings onOpenMembers={() => openSection("members")} />}
            {section === "centers" && isSuperadmin && <Centers />}
          </Suspense>
        </div>
      </main>
    </div>
  );
}

// 셸이 인쇄하는 센터 상호(P55) — 사이드바와 헤더 두 곳이 **같은 컴포넌트**를 쓴다.
//
// 별도 컴포넌트인 이유는 HeaderIdentity와 같다: App 본체(AdminShell)에서 훅을 부르면 인증 게이트
// 앞이라 로그인 화면에서도 /v1/center를 401로 때린다. 셸 안에서만 마운트하면 인증 통과 뒤에만
// 조회가 나가고, 쿼리 키(keys.center)가 대시보드·예약·설정과 같아 TanStack이 중복 요청을 합친다
// (매출·홈워크·체형 탭에서만 이 조회가 새로 뜬다 — 상호를 얻을 더 싼 출처가 없다. /v1/me는
// 사람 이름만 싣는다).
//
// 폴백은 centerDisplayName 한 곳에 있다: 조회 실패·로딩 중·상호 미등록이 모두 같은 문자열로
// 접히므로 헤더가 빈칸이 되거나 로딩 동안 이름이 깜빡이지 않는다.
function CenterName() {
  const centerQ = useCenter();
  return <>{centerDisplayName(centerQ.data)}</>;
}

// 네비 "회원 관리"의 가입 요청 대기 배지(P69). CenterName과 같은 이유로 별도 컴포넌트다 — 셸 본체에서
// 훅을 부르면 인증 게이트 앞이라 로그인 화면에서 /v1/join/requests를 401로 때린다. 렌더 조건(isOwner)
// 이 마운트 게이트라 트레이너 세션에서는 조회 자체가 없고, 쿼리 키가 대시보드·회원 관리 큐와 같아
// 추가 요청은 없다(1분 폴링도 그쪽과 하나로 합쳐진다). 판정도 같다(isJoinPending) — 배지·큐·대시보드가
// 다른 수를 말하면 안 된다. 0건·로딩·실패는 배지 없음(실패는 대시보드가 문장으로 말한다).
function NavJoinBadge() {
  const joinReqQ = useJoinRequests();
  const count = (joinReqQ.data ?? []).filter(isJoinPending).length;
  if (count === 0) return null;
  return (
    <span
      className="ml-auto inline-flex min-w-[18px] items-center justify-center rounded-full bg-brand px-1.5 text-[10.5px] font-extrabold leading-[18px] text-bg"
      title={`앱 가입 요청 ${count}건 대기`}
    >
      {count}
    </span>
  );
}

// 헤더의 내 표시 이름 — 1순위는 /v1/me의 name(계약 v2.2)이고, 없을 때만 종전 사슬로 내려간다:
// staff 목록(uid→이름) → 데모 identity.name → Firebase 이메일 → uid.
// 실계정 로그인 시 identity가 null이라 이 해석이 없으면 이메일 원문(rizejoy91@gmail.com)이
// 헤더에 그대로 노출된다 — 그래서 사슬은 끝까지 남긴다.
//
// v2.2의 이득은 **의존이 끊긴다는 것**이다. 종전엔 이름 하나를 얻으려고 셸이 항상 /v1/staff를
// 불렀고(대시보드·회원·예약·설정은 목록을 어차피 쓰지만 매출·홈워크·체형 탭은 헤더 때문에만
// 불렀다), 목록이 도착하기 전까지 헤더는 이메일을 보여주다 이름으로 바뀌었다. 이제 name이
// 오면 첫 렌더부터 이름이고 조회는 아예 일어나지 않는다(useStaff(enabled)).
// name이 비어 오는 응답(서버측 이름 조회 실패·구버전 서버)에서만 조인을 켠다 — me는 셸 진입
// 조건(isAuthed)이라 이 컴포넌트의 첫 렌더에 이미 확정돼 있어, 켜짐/꺼짐이 도중에 뒤집히며
// 헤더가 깜빡이지 않는다.
// 셸(인증 통과) 안에서만 마운트되는 별도 컴포넌트다 — App 본체에서 훅을 부르면 로그인 화면에서도
// /v1/staff를 401로 때린다. 쿼리 키는 다른 화면과 동일해 TanStack이 중복 요청을 합친다.
function HeaderIdentity() {
  const { me, identity, fbEmail } = useAuth();
  const meName = firstNonEmpty(me?.name);
  const staffQ = useStaff(!meName);
  const staffName = staffQ.data?.find((s) => s.uid === me?.uid)?.name;
  return (
    <span className="hidden text-[11px] text-muted sm:inline">
      {firstNonEmpty(meName, staffName, identity?.name, fbEmail, me?.uid)}
    </span>
  );
}
