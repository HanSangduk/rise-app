// 어드민 셸 — 인증 게이트 → 사이드바 레이아웃(반응형: <880px 상단 가로 네비) → 역할별 메뉴.
// 라우팅은 wodshot web과 동일하게 상태 기반 탭(딥링크 불필요 규모 — TanStack Router 승격은 보류).
import { useEffect, useMemo, useState } from "react";
import {
  BarChart3,
  CalendarDays,
  Camera,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  Settings as SettingsIcon,
  Users,
  type LucideIcon,
} from "lucide-react";
import { BrandMark } from "@/components/BrandMark";
import { Spinner } from "@/components/ui";
import { cn } from "@/lib/cn";
import { DEMO_OWNER, DEMO_TRAINER, useAuth } from "@/lib/auth";
import { firstNonEmpty } from "@/lib/format";
import { useStaff } from "@/lib/queries";
import { Login } from "@/features/Login";
import { NoAccess } from "@/features/NoAccess";
import { Dashboard } from "@/features/Dashboard";
import { Schedule } from "@/features/Schedule";
import { Members } from "@/features/Members";
import { Sales } from "@/features/Sales";
import { Homework } from "@/features/Homework";
import { BodyPhotos } from "@/features/BodyPhotos";
import { Settings } from "@/features/Settings";

type Section = "dash" | "cal" | "members" | "sales" | "hw" | "body" | "set";

const NAV: { id: Section; label: string; icon: LucideIcon; ownerOnly?: boolean }[] = [
  { id: "dash", label: "대시보드", icon: LayoutDashboard },
  { id: "cal", label: "예약 (3팀/시간)", icon: CalendarDays },
  { id: "members", label: "회원 관리", icon: Users },
  { id: "sales", label: "매출·통계", icon: BarChart3, ownerOnly: true },
  { id: "hw", label: "Home Work", icon: ClipboardList },
  { id: "body", label: "체형 분석", icon: Camera },
  { id: "set", label: "설정·직원", icon: SettingsIcon, ownerOnly: true },
];

const TITLES: Record<Section, string> = {
  dash: "대시보드",
  cal: "예약",
  members: "회원 관리",
  sales: "매출·통계",
  hw: "Home Work",
  body: "체형 분석",
  set: "설정·직원",
};

export default function App() {
  // fbEmail은 헤더 표시 이름의 폴백으로만 쓰여 HeaderIdentity가 직접 읽는다.
  const { me, identity, isLoading, isAuthed, loginDev, logout } = useAuth();
  const [section, setSection] = useState<Section>("dash");
  // 대시보드 "해야 할 일"에서 회원 이름 클릭 → 회원 관리 탭 + 해당 회원 상세(v1.4 UX 여정 마감).
  // 섹션 전환 시 Members가 리마운트되므로 초기 선택값 prop으로 충분하다(CustomEvent 불필요).
  const [memberFocusId, setMemberFocusId] = useState<string | null>(null);

  const isOwner = me?.role === "owner";
  // 어드민을 쓸 수 있는 역할은 스태프(대표·트레이너)뿐 — role=member는 셸에 들이지 않는다.
  const isStaff = me?.role === "owner" || me?.role === "trainer";
  const nav = useMemo(() => NAV.filter((n) => !n.ownerOnly || isOwner), [isOwner]);

  function openMember(memberId: string) {
    setMemberFocusId(memberId);
    setSection("members");
  }

  // 탭 이동(네비 클릭·대시보드 온보딩/할 일 링크 공용) — 대시보드발 회원 포커스를 지운다.
  // 남겨두면 다음 회원 관리 진입 시 이전 포커스가 되살아나는 잔상이 생긴다.
  function openSection(id: Section) {
    setMemberFocusId(null);
    setSection(id);
  }

  // 트레이너로 전환되어 대표 전용 화면(매출·설정)에 남아있으면 대시보드로 되돌린다(목업 setRole 동작과 동일).
  useEffect(() => {
    if (!nav.some((n) => n.id === section)) setSection("dash");
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
  if (!isStaff) return <NoAccess />;

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
          <div className="text-[10.5px] text-muted">라이즈 컨디셔닝 센터 (강남)</div>
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
          </button>
        ))}
      </aside>

      {/* 본문 */}
      <main className="min-w-0 flex-1">
        <header className="flex flex-wrap items-center justify-between gap-2.5 border-b border-line bg-panel px-5 py-2.5">
          <div className="text-[13px] text-muted">
            라이즈 컨디셔닝 · <b className="text-ink">{TITLES[section]}</b>
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
                    isOwner ? "bg-brand text-white" : "text-muted hover:text-ink",
                  )}
                >
                  대표 {DEMO_OWNER.name}
                </button>
                <button
                  onClick={() => void loginDev(DEMO_TRAINER)}
                  className={cn(
                    "rounded-full px-3 py-1 text-[11.5px] font-extrabold transition",
                    !isOwner ? "bg-brand text-white" : "text-muted hover:text-ink",
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
          {section === "dash" && (
            <Dashboard
              onOpenMember={openMember}
              onOpenMembers={() => openSection("members")}
              // 설정 탭은 대표 전용이라 트레이너에겐 콜백 자체를 주지 않는다 — 화면에서
              // 눌러봐야 되돌려지는 데드 링크를 만들지 않는다(대시보드도 owner 게이트를 건다).
              onOpenSettings={isOwner ? () => openSection("set") : undefined}
            />
          )}
          {section === "cal" && <Schedule />}
          {section === "members" && <Members focusMemberId={memberFocusId} />}
          {section === "sales" && isOwner && <Sales />}
          {section === "hw" && <Homework />}
          {section === "body" && <BodyPhotos />}
          {section === "set" && isOwner && <Settings />}
        </div>
      </main>
    </div>
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
