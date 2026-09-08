// 대시보드 — 목업 s-dash 1:1. owner=센터 KPI 6종+전체 일정, trainer=내 수업·내정산·내통계.
// "계약서 미서명"은 v1.1 정합 패치의 Contract 엔티티(GET /v1/contracts?status=sent)로 실데이터화했다.
// 회원 동의(consent) 미완료는 계약 서명과 별개 항목이라 그대로 유지한다.
import { useMemo, useState } from "react";
import { ArrowRight, Check, RefreshCw } from "lucide-react";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  ErrorState,
  ProgressBar,
  Spinner,
  TD,
  TH,
  THead,
  TR,
  Table,
} from "@/components/ui";
import { useAuth } from "@/lib/auth";
import {
  useCenter,
  useCheckin,
  useContracts,
  useConsultDone,
  useConsultRequests,
  useJoinRequests,
  useMembers,
  usePayments,
  useSlots,
  useStaff,
  useStats,
} from "@/lib/queries";
import {
  firstNonEmpty,
  formatCurrency,
  formatDateWithDow,
  formatPercent,
  ratioState,
  staffLabel,
  todayStr,
} from "@/lib/format";
import {
  isJoinPending,
  isPassBookable,
  type BookingKind,
  type MemberWithPasses,
  type Stats,
} from "@/lib/types";

const KIND_LABEL: Record<BookingKind, string> = { pt: "1:1", group: "그룹", ot: "체험(OT)" };

export function Dashboard({
  onOpenMember,
  onOpenMembers,
  onOpenJoinRequest,
  onOpenSettings,
}: {
  onOpenMember?: (memberId: string) => void;
  /** 회원 관리 탭으로 이동(포커스 없음) — 빈 센터 온보딩 "첫 회원 등록" · 가입 요청 대기 줄. */
  onOpenMembers?: () => void;
  /** 회원 관리 탭 + 상단 가입 요청 큐에서 그 요청 행 강조(P69) — 대표에게만 전달된다. */
  onOpenJoinRequest?: (requestId: string) => void;
  /** 설정·직원 탭으로 이동 — 대표에게만 전달된다(트레이너에겐 undefined = 링크 없음). */
  onOpenSettings?: () => void;
}) {
  const { me, identity } = useAuth();
  const isOwner = me?.role === "owner";
  const today = todayStr();

  const centerStats = useStats("ytd", "center");
  const meStats = useStats("ytd", "me");
  // Home Work 완료율 카드가 보는 스코프 — 대표는 센터 전체, 트레이너는 본인 담당분.
  const hwScopeStats = isOwner ? centerStats : meStats;
  // 카드가 무엇을 그릴지는 값이 아니라 **상태**가 정한다(format.ts ratioState — 값/집계 대상 0/미상).
  // 응답 전(undefined)은 아래 로딩 분기가 따로 받는다.
  const hwView = hwScopeStats.data
    ? ratioState(hwScopeStats.data.hw_rate, hwScopeStats.data.hw_d)
    : null;
  const slotsQ = useSlots(today);
  const staffQ = useStaff();
  const membersQ = useMembers();
  // v1.1: 서명 대기(sent) 계약 — "계약서 미서명" 실데이터. 역할 스코프는 다른 GET처럼 서버가 자동 처리.
  // v1.5: 환불로 무효(voided)된 계약은 status=sent 서버 필터에서 자동 제외. 다만 그 전이가 닿지
  // 못한 refunded 패스의 잔존 sent는 그대로 온다 — 아래 pendingContracts가 거른다(P38).
  // P40: 탈퇴도 남은 draft·sent를 서버가 void한다 — 탈퇴 회원의 잔존 sent 역시 이 필터에서
  // 사라지므로, 이름이 안 풀리는 계약으로 남는 건 담당 이관 드리프트뿐이다(카드 렌더 참조).
  const pendingContractsQ = useContracts(undefined, "sent");
  // v1.5: 결제 기록 없는 회원권 감시(owner 전용) — 전체 결제 목록 + 회원 임베드 passes 조인.
  // 트레이너에겐 null로 조회 자체를 끈다(undefined = 전체 조회, null = 비활성 — usePayments 규약).
  const allPaymentsQ = usePayments(isOwner ? undefined : null);
  // 대기 중인 가입 요청 — 회원 앱은 "센터에서 승인하면 연결돼요"라고 약속해놓고, 대표 쪽엔
  // 큐를 직접 열어야 보이는 배지뿐이었다(두 화면의 약속이 어긋남). 해야 할 일로 끌어올린다.
  // 큐 자체는 회원 관리 탭 최상단에 있다(P69, JoinRequests.tsx) — 이 줄은 거기로 가는 문이다.
  // owner 전용 API라 트레이너에겐 조회 자체를 끈다(403 → "조회 실패" 노출 방지).
  const joinReqQ = useJoinRequests(isOwner);
  // 재등록 요청(계약 v2.20, P42) — 앱 CTA가 "센터에서 연락드릴 거예요"라고 약속한다.
  // 가입 요청과 같은 이유로 해야 할 일에 놓는다. owner 게이트 없음 — 서버가 역할 스코프를
  // 정한다(owner 전체 / trainer 담당 회원만).
  const consultQ = useConsultRequests();
  const consultDone = useConsultDone();
  // 체크인 성공한 예약 — 서버에 조회 API가 없어(체크인은 출석 기록만) 세션 로컬로 표시 상태를 든다.
  // 새로고침하면 초기화되지만 "눌렀는데 반응 없음 → 중복 탭" 혼선은 막는다.
  // P40: 마킹은 훅-레벨 콜백으로 — mutate-레벨 onSuccess는 다음 mutate()가 옵저버를 떼는
  // 순간 실행되지 않아(react-query v5) 연속 체크인에서 앞선 건의 "체크인됨"이 유실됐다
  // (isPending 전체 잠금이 창을 좁히긴 하나 리렌더 전 연속 클릭은 못 막는다). 발송 마킹
  // (Members.tsx sentMarkIds)의 원조 패턴이라 같은 수리를 함께 받는다.
  const [checkedInIds, setCheckedInIds] = useState<Set<string>>(new Set());
  const checkin = useCheckin((bookingId) =>
    setCheckedInIds((prev) => new Set(prev).add(bookingId)),
  );
  // 기준일(재등록 인정·장기 미출석·만료 임박)은 센터 정책 실값 — 하드코딩 카피가 정책 편집(v1.4)과
  // 어긋나지 않게 한다. 정책 로딩 전엔 시드 기본값(90/60/7) 폴백.
  const centerQ = useCenter();
  const policy = centerQ.data?.policy;
  const reregWindowDays = policy?.rereg_window_days ?? 90;
  const longAbsentDays = policy?.long_absent_days ?? 60;
  const expiringDays = policy?.expiring_days ?? 7;

  // 원본 이름(퇴사 표식 없음) — v2.2 이후로는 아래 myName의 **폴백**으로만 쓰인다.
  const staffName = useMemo(() => {
    const map = new Map<string, string>();
    for (const s of staffQ.data ?? []) map.set(s.uid, s.name);
    return map;
  }, [staffQ.data]);
  // 일정 표의 담당 열은 **기존 데이터 표시**라 퇴사자도 계속 해석하되 "(퇴사)"를 붙인다(v2.0).
  // 위 staffName(원본 이름)과 나눠 둔다 — myName까지 "(퇴사)"가 붙으면 헤더 인사말이 이상해진다.
  const staffDisplay = useMemo(() => {
    const map = new Map<string, string>();
    for (const s of staffQ.data ?? []) map.set(s.uid, staffLabel(s));
    return map;
  }, [staffQ.data]);
  // 내 표시 이름(트레이너 인사말·"내 정산" 라벨) — 헤더(App.tsx HeaderIdentity)와 같은 우선순위:
  // /v1/me의 name(계약 v2.2) → staff 목록 조인 → 데모 identity.name.
  // name이 오면 staff 목록이 아직 안 왔어도 첫 렌더부터 "정혜린 코치님"으로 뜬다(종전엔 목록이
  // 도착할 때까지 실계정 로그인에서 identity가 null이라 인사말이 "코치님,"으로 시작했다).
  //
  // 헤더와 달리 여기서 사슬을 fbEmail·uid로 더 내리지 **않는다**: 이 값은 "OOO 코치님" 호칭과
  // "내 정산 (OOO)" 라벨에 들어가는 자리라 이메일 원문이나 uid가 들어가면 감추려던 것을 문장
  // 한가운데에 다시 노출한다. 마지막 폴백은 종전대로 빈 문자열이고, 호출부가 그 상태를
  // 흡수한다(인사말은 trimStart, 정산 라벨은 "-").
  const myName = firstNonEmpty(me?.name, staffName.get(me?.uid ?? ""), identity?.name) ?? "";
  const memberName = useMemo(() => {
    const map = new Map<string, string>();
    for (const m of membersQ.data ?? []) map.set(m.id, m.name);
    return map;
  }, [membersQ.data]);

  // 오늘 팀(레인) 목록 — 시간순 정렬, 트레이너는 본인 수업만.
  const todayTeams = useMemo(() => {
    const rows = (slotsQ.data ?? []).flatMap((slot) =>
      slot.teams.map((team) => ({ slot, team })),
    );
    const scoped = isOwner ? rows : rows.filter((r) => r.team.trainer_id === me?.uid);
    return scoped.sort((a, b) => a.slot.slot_key.localeCompare(b.slot.slot_key));
  }, [slotsQ.data, isOwner, me?.uid]);

  const doneCount = todayTeams.filter((r) => (r.team.status ?? "confirmed") === "completed").length;
  const noshowCount = todayTeams.filter((r) => (r.team.status ?? "confirmed") === "noshow").length;

  // 해야 할 일 — 회원(+패스) 데이터에서 파생. 트레이너는 이미 담당만 스코프됨(API계약: 역할 스코프 자동).
  const todo = useMemo(
    () => computeTodo(membersQ.data ?? [], { expiringDays, longAbsentDays }),
    [membersQ.data, expiringDays, longAbsentDays],
  );
  // P38(P36): refunded 패스에 남은 잔존 sent 계약은 할 일에서 뺀다 — 회원권이 이미 환불된
  // 거래는 서명 받을 일이 없다(앱 contracts_row가 이미 하는 판정 — 어드민만 세던 비대칭 해소).
  // 판정 재료는 membersQ 임베드 passes뿐이라 새 조회가 없다. 패스를 못 찾은 계약은 빼지
  // 않는다 — 모르는 것을 "처리 불요"로 단정하지 않는다.
  const pendingContracts = useMemo(() => {
    const refundedPassIds = new Set(
      (membersQ.data ?? []).flatMap((m) =>
        m.passes.filter((p) => p.status === "refunded").map((p) => p.id),
      ),
    );
    return (pendingContractsQ.data ?? []).filter((c) => !refundedPassIds.has(c.pass_id));
  }, [pendingContractsQ.data, membersQ.data]);
  const pendingContractsCount = pendingContracts.length;
  // 승인 대기 건수 — **응답 길이가 아니라 상태로 센다**(P55).
  //
  // 종전 주석은 "GET /v1/join/requests는 승인 대기분만 반환한다(승인 시 목록에서 사라짐)"였는데
  // 그게 사실이 아니었다: 서버 store.ListJoinRequests에 상태 조건이 없어 승인·거절된 요청까지
  // 그대로 내려온다. 그래서 이 숫자는 처리해도 줄지 않았고, 대표는 "승인" 링크를 눌러
  // 이미 처리한 사람만 있는 큐를 다시 봤다. 서버가 pending만 주게 되면(P55 백엔드) 이 판정은
  // 아무것도 거르지 않는 no-op가 되고, 그 전까지는 회원 관리의 큐·네비 배지와 **같은 수**를 말한다.
  // 정렬도 큐와 같다(먼저 온 순) — 여기 실린 이름 셋이 큐의 첫 세 줄이다.
  const pendingJoins = (joinReqQ.data ?? [])
    .filter(isJoinPending)
    .sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
  const pendingJoinCount = pendingJoins.length;
  // 재등록 요청은 done 이력도 응답에 남는다 — 할 일은 pending만.
  const pendingConsults = (consultQ.data ?? []).filter((r) => r.status === "pending");
  // 빈 센터 온보딩 판정 — data가 실제로 도착해 "0명"임을 확인했을 때만 참이다. isLoading으로
  // 판정하면 첫 렌더의 undefined를 0명으로 오독해 카드가 번쩍였다 사라진다(로딩·에러 중엔 undefined).
  const isEmptyCenter = isOwner && membersQ.data?.length === 0;
  // v1.5 재정의: unpaid_count = "연체"(due 경과) 회차가 있는 결제 건수(owner 전용 — 트레이너 응답에선 0).
  const unpaidCount = centerStats.data?.unpaid_count ?? 0;
  // v1.5: 발급만 되고 결제 기록이 0건인 active 회원권 — 장부 누락(유령 매출) 감시(owner 전용).
  // 결제 목록 로딩 전엔 빈 배열 — "전부 미기록"으로 오탐하지 않는다.
  const unrecordedPasses = useMemo(() => {
    if (!isOwner || !allPaymentsQ.data) return [];
    const recordedPassIds = new Set(allPaymentsQ.data.map((pay) => pay.pass_id));
    return (membersQ.data ?? []).flatMap((m) =>
      m.passes
        // scheduled(선판매)도 돈은 받은 회원권이다 — 빼면 미기록 매출이 사라진다(P25).
        .filter((p) => isPassBookable(p) && !recordedPassIds.has(p.id))
        .map((pass) => ({ member: m, pass })),
    );
  }, [isOwner, allPaymentsQ.data, membersQ.data]);

  const isLoading = (isOwner ? centerStats.isLoading : meStats.isLoading) || slotsQ.isLoading;

  return (
    <div>
      <div className="mb-3.5 flex items-start justify-between gap-3">
        <div>
          <h2 className="text-[16.5px] font-bold">대시보드</h2>
          <p className="mt-0.5 text-xs text-muted">
            {isOwner
              ? "센터 건강 상태 한눈에 — 회원·리텐션·오늘."
              : `${myName} 코치님, 오늘 내 수업과 담당 회원 현황입니다.`.trimStart()}
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            void centerStats.refetch();
            void meStats.refetch();
            void slotsQ.refetch();
            // "해야 할 일"(회원·계약 파생)도 함께 갱신 — stats/slots만 갱신하면 반쪽 새로고침이 된다.
            void membersQ.refetch();
            void pendingContractsQ.refetch();
            // **이 화면이 그리는 것은 전부 다시 불러온다.** 종전엔 재등록 요청·정책·직원이 빠져
            // 있었는데, 정작 재등록 요청 조회 실패 문구가 "새로고침 후 확인해주세요"라고 이
            // 버튼을 가리켰다 — 눌러도 그 조회는 다시 시도되지 않는 막다른 안내였다.
            // 정책(기준일 카피)·직원(담당 이름)도 이 화면의 표시 내용이라 함께 맞춘다.
            void consultQ.refetch();
            void centerQ.refetch();
            void staffQ.refetch();
            // 결제 기록 없는 회원권(결제 파생)·가입 요청 — refetch()는 enabled를 우회하므로 owner만.
            if (isOwner) {
              void allPaymentsQ.refetch();
              void joinReqQ.refetch();
            }
          }}
        >
          <RefreshCw className="h-3.5 w-3.5" /> 새로고침
        </Button>
      </div>

      {/* 빈 센터 첫 화면 — 0짜리 KPI 6개 앞에 "다음에 할 일"을 놓는다. 첫 할 일(트레이너 초대·
          회원 등록)이 설정 탭 안쪽에 숨어 있어 발견이 어려웠다. 회원이 생기면 자동으로 사라진다. */}
      {isEmptyCenter && (
        <Card className="mb-3.5 border-brand/30 bg-brand/[0.08]">
          <CardHeader>
            <CardTitle>센터 시작하기 — 3단계</CardTitle>
            <Badge tone="brand">회원 0명</Badge>
          </CardHeader>
          <CardContent>
            <p className="mb-2.5 text-[11.5px] leading-relaxed text-muted">
              아직 등록된 회원이 없어 아래 지표는 모두 비어 있습니다. 순서대로 진행하면 오늘부터
              예약·수업 기록이 쌓입니다.
            </p>
            <div className="grid gap-2 sm:grid-cols-3">
              <OnboardingStep
                n={1}
                title="트레이너 초대"
                desc="설정 · 직원에서 메일로 초대하면 비밀번호 설정 후 바로 합류합니다."
                actionLabel="설정 탭 열기"
                onClick={onOpenSettings}
              />
              <OnboardingStep
                n={2}
                title="첫 회원 등록"
                desc="등록하면 끝 — 앱에서 번호 인증 시 자동으로 연결됩니다."
                actionLabel="회원 탭 열기"
                onClick={onOpenMembers}
              />
              <OnboardingStep
                n={3}
                title="운영 정책 확인"
                desc="시간당 팀 수·취소 마감·위약금율을 센터에 맞게 맞춰주세요."
                actionLabel="설정 탭 열기"
                onClick={onOpenSettings}
              />
            </div>
          </CardContent>
        </Card>
      )}

      {isOwner && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-6">
          {centerStats.isLoading ? (
            <div className="col-span-full">
              <Spinner />
            </div>
          ) : centerStats.isError ? (
            <div className="col-span-full">
              <ErrorState error={centerStats.error} onRetry={() => void centerStats.refetch()} />
            </div>
          ) : (
            centerStats.data && (
              <KpiCards
                stats={centerStats.data}
                reregWindowDays={reregWindowDays}
                longAbsentDays={longAbsentDays}
                expiringDays={expiringDays}
              />
            )
          )}
        </div>
      )}

      <div className="mt-3.5 grid gap-3 lg:grid-cols-[3fr_2fr]">
        {/* 오늘 일정 */}
        <Card>
          <CardHeader>
            <CardTitle className="flex flex-wrap items-center gap-1.5">
              오늘 일정
              {isOwner ? (
                <>
                  <Badge tone="brand">{todayTeams.length}팀</Badge>
                  <Badge tone="ok">출석 {doneCount}</Badge>
                  <Badge tone="danger">노쇼 {noshowCount}</Badge>
                </>
              ) : (
                <>
                  <Badge tone="brand">내 {todayTeams.length}팀</Badge>
                  <Badge tone="danger">노쇼 {noshowCount}</Badge>
                </>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {slotsQ.isLoading ? (
              <Spinner />
            ) : slotsQ.isError ? (
              <ErrorState error={slotsQ.error} onRetry={() => void slotsQ.refetch()} />
            ) : !todayTeams.length ? (
              <EmptyState>오늘 예정된 일정이 없습니다.</EmptyState>
            ) : (
              <Table>
                <THead>
                  <TR>
                    <TH>시간</TH>
                    <TH>팀</TH>
                    <TH>트레이너</TH>
                    <TH>상태</TH>
                    <TH></TH>
                  </TR>
                </THead>
                <tbody>
                  {todayTeams.map(({ slot, team }) => {
                    const status = team.status ?? "confirmed";
                    const hour = slot.slot_key.split("-")[1] ?? "";
                    const isCheckedIn = checkedInIds.has(team.booking_id);
                    return (
                      <TR key={team.booking_id}>
                        <TD>{hour}:00</TD>
                        <TD>
                          {memberName.get(team.member_id) ?? (membersQ.isLoading ? "…" : team.member_id)}{" "}
                          {KIND_LABEL[team.kind]}
                        </TD>
                        <TD>{staffDisplay.get(team.trainer_id) ?? (staffQ.isLoading ? "…" : team.trainer_id)}</TD>
                        <TD>
                          {status === "completed" && <Badge tone="ok">완료</Badge>}
                          {status === "noshow" && <Badge tone="danger">노쇼</Badge>}
                          {status === "confirmed" && <Badge tone="warn">예정</Badge>}
                        </TD>
                        <TD>
                          {status === "confirmed" && (
                            <Button
                              size="sm"
                              variant={isCheckedIn ? "outline" : "default"}
                              disabled={isCheckedIn || checkin.isPending}
                              onClick={() =>
                                checkin.mutate({ source: "tap", booking_id: team.booking_id })
                              }
                            >
                              <Check className="h-3 w-3" /> {isCheckedIn ? "체크인됨" : "체크인"}
                            </Button>
                          )}
                          {/* 유예는 백엔드가 최초 1회 자동 적용(noshow_waived) — 수동 재호출 시 이중 차감이라 버튼 없음. */}
                          {status === "noshow" && (
                            <span className="text-[10.5px] text-muted">최초 1회 자동 유예</span>
                          )}
                        </TD>
                      </TR>
                    );
                  })}
                </tbody>
              </Table>
            )}
            {checkin.isError && (
              <p className="mt-2 text-[11px] text-danger">체크인 실패: {checkin.error.message}</p>
            )}
            <p className="mt-2.5 text-[10.5px] leading-relaxed text-muted">
              체크인 = 출석 기록(세션 차감은 완료 처리 시).{" "}
              {!isOwner && <b className="text-brand">내 수업만 표시됩니다.</b>}
              {isOwner && "트레이너 뷰에선 본인 수업만 보입니다."}
            </p>
          </CardContent>
        </Card>

        {/* 해야 할 일 */}
        <Card>
          <CardHeader>
            <CardTitle>해야 할 일</CardTitle>
          </CardHeader>
          <CardContent>
            {membersQ.isLoading || pendingContractsQ.isLoading ? (
              <Spinner />
            ) : membersQ.isError || pendingContractsQ.isError ? (
              // 에러를 "처리할 항목 없음"으로 위장하지 않는다 — 리텐션 액션 누락은 매출 손실.
              <ErrorState error={membersQ.error ?? pendingContractsQ.error} onRetry={() => { void membersQ.refetch(); void pendingContractsQ.refetch(); }} />
            ) : (
              <div className="space-y-2 text-xs leading-relaxed">
                {/* 앱 회원이 "센터에서 승인하면 연결돼요" 안내를 받고 기다리는 중 — 가장 먼저 놓는다. */}
                {isOwner && pendingJoinCount > 0 && (
                  // 재등록 요청 줄과 같은 형식(P69) — 이름 3개까지, 번호는 싣지 않는다(같은 owner
                  // 게이트라 노출 범위는 큐와 같지만 대시보드는 훑어보는 화면이다). 이름 클릭은 큐의
                  // 그 행으로, 꼬리 링크는 회원 관리 탭으로.
                  <div className="text-brand">
                    가입 요청 대기 <b>{pendingJoinCount}건</b> —{" "}
                    {pendingJoins.slice(0, 3).map((r, i) => (
                      <span key={r.id}>
                        {i > 0 && " · "}
                        <NameLink
                          name={r.name}
                          onClick={onOpenJoinRequest && (() => onOpenJoinRequest(r.id))}
                        />
                      </span>
                    ))}
                    {pendingJoinCount > 3 && <span className="text-muted"> 외 {pendingJoinCount - 3}명</span>}{" "}
                    → <NameLink name="회원 관리에서 처리" onClick={onOpenMembers} />
                  </div>
                )}
                {/* 가입 요청 조회 실패를 "대기 없음"으로 위장하지 않는다 — 앱에서 기다리는 회원이 있다.
                    종전엔 "직접 확인해주세요"라고 다른 탭으로 보냈는데, 회원 관리 상단의 가입 요청
                    큐는 **같은 조회**를 쓴다(useJoinRequests) — 가서 봐도 똑같이 실패한다. 갈 데가
                    없는 안내 대신 이 화면에서 할 수 있는 한 가지(위 새로고침)만 말한다. */}
                {isOwner && joinReqQ.isError && (
                  <div className="text-muted">
                    가입 요청을 불러오지 못했어요 — 기다리는 회원이 있는지 지금은 알 수 없어요.
                    위 <b>새로고침</b>을 눌러 다시 시도해주세요.
                  </div>
                )}
                {/* 재등록 요청(v2.20) — 회원이 앱에서 직접 손든 목록. 아래 "잔여 부족 — 재계약
                    상담"이 센터가 찍은 후보라면 이쪽은 이미 의사가 확인된 사람이라 우선순위가
                    높다(가입 요청 바로 다음). 상담을 마치면 [완료]로 큐에서 내린다 — 발급·결제는
                    회원 상세의 기존 수기 플로우가 담당한다. */}
                {pendingConsults.length > 0 && (
                  <div className="text-brand">
                    재등록 요청 <b>{pendingConsults.length}건</b> —{" "}
                    {pendingConsults.slice(0, 3).map((r, i) => {
                      // 진행·실패는 **이 요청 행**만 본다(Members.tsx 계약 발송·회차 납부와 같은
                      // variables 식별 패턴). 종전엔 isPending 하나로 세 줄의 버튼이 함께 잠기고,
                      // 실패는 **어디에도 그려지지 않았다** — 버튼이 다시 살아나고 줄도 그대로라
                      // 대표에게는 "안 눌렸다"로 보였고, 눌러도 같은 실패가 조용히 반복됐다.
                      const isThis = consultDone.variables === r.id;
                      const rowPending = consultDone.isPending && isThis;
                      const rowFailed = consultDone.isError && isThis;
                      return (
                        <span key={r.id}>
                          {i > 0 && " · "}
                          {r.member_name ? (
                            <NameLink
                              name={r.member_name}
                              onClick={onOpenMember && (() => onOpenMember(r.member_id))}
                            />
                          ) : (
                            // 탈퇴 등으로 이름을 못 푸는 요청(owner 응답에만 잔존) — 죽은 링크를
                            // 만들지 않는다(계약서 미서명 줄과 같은 규약).
                            <span className="text-muted">(조회 불가)</span>
                          )}
                          {r.note && <span className="text-muted"> “{r.note}”</span>}{" "}
                          <button
                            type="button"
                            className="text-muted underline disabled:opacity-50"
                            disabled={rowPending}
                            onClick={() => consultDone.mutate(r.id)}
                          >
                            {rowPending ? "처리 중…" : "완료"}
                          </button>
                          {/* 실패해도 버튼은 살아 있다 — 같은 자리에서 바로 다시 누를 수 있다. */}
                          {rowFailed && (
                            <span className="block text-danger">
                              {r.member_name ? `${r.member_name} 님 ` : ""}완료 처리를 못 했어요:{" "}
                              {consultDone.error.message} — 위 <b>완료</b>를 다시 눌러주세요.
                            </span>
                          )}
                        </span>
                      );
                    })}
                    {pendingConsults.length > 3 && ` 외 ${pendingConsults.length - 3}건`}
                  </div>
                )}
                {/* 요청 조회 실패를 "대기 없음"으로 위장하지 않는다 — 앱은 "연락드릴 거예요"라고 약속했다.
                    이제 위 새로고침 버튼이 이 조회도 실제로 다시 부른다(refetch 목록 참고) — 문구가
                    가리키는 행동이 실제로 작동하는 행동과 같아야 한다. */}
                {consultQ.isError && (
                  <div className="text-muted">
                    재등록 요청을 불러오지 못했어요 — 앱에서 연락을 기다리는 회원이 있는지 지금은 알
                    수 없어요. 위 <b>새로고침</b>을 눌러 다시 시도해주세요.
                  </div>
                )}
                {/* P38(P36 H): 건수만 말하고 끊기던 여정 — 이웃 "결제 기록 없는 회원권"과 같은
                    NameLink로 회원 상세 직행. 한 회원의 계약 여러 건은 건별로 반복 표기한다
                    (이웃 카드가 패스 건별로 늘어놓는 규약 그대로 — 건수와 이름 수가 어긋나지 않는다). */}
                {pendingContractsCount > 0 && (
                  <div>
                    계약서 미서명 <b>{pendingContractsCount}건</b> (
                    {pendingContracts.slice(0, 3).map((c, i) => {
                      // P40: 이름이 안 풀리는 계약은 링크를 만들지 않는다. 회원 목록은
                      // member.trainer_id축, 계약은 pass.trainer_id축이라 회원만 타 담당으로
                      // 이관되면 여기서 이름이 안 풀린다 — 종전엔 원시 member_id가 NameLink로
                      // 떠서 눌러도 회원 관리에서 찾을 수 없는 죽은 링크였고, id 원문은 운영자에게
                      // 아무 정보도 아니다. 건수는 그대로 센다 — 이름을 못 푼다고 할 일이
                      // 사라지는 게 아니다(이 목록은 이 화면이 뜰 때 membersQ 로딩이 이미 끝난
                      // 분기 안이라 "로딩 중이라 안 풀림"은 없다).
                      const name = memberName.get(c.member_id);
                      return (
                        <span key={c.id}>
                          {i > 0 && "·"}
                          {name ? (
                            <NameLink
                              name={name}
                              onClick={onOpenMember && (() => onOpenMember(c.member_id))}
                            />
                          ) : (
                            <span className="text-muted">(조회 불가)</span>
                          )}
                        </span>
                      );
                    })}
                    {/* P40: 3건까지만 보여주던 목록이 초과분을 조용히 삼켰다 — 굵은 건수와
                        괄호 안 이름 수가 어긋나면 숫자를 못 믿게 된다. 잘린 만큼을 말한다. */}
                    {pendingContractsCount > 3 && ` 외 ${pendingContractsCount - 3}건`}
                    ) — 회원 상세에서 재발송 처리
                  </div>
                )}
                {/* v1.5 재정의: 연체(due 경과)만 카운트 — 미도래 분할 회차는 할 일이 아니다. */}
                {isOwner && unpaidCount > 0 && (
                  <div className="text-warn">
                    연체 미납 <b>{unpaidCount}건</b> — 회원 상세에서 납부 처리
                  </div>
                )}
                {/* 결제 조회 실패를 "감시 항목 없음"으로 위장하지 않는다 — 실패를 명시하고
                    나머지 할 일 렌더는 유지한다(무결제 감시만 일시 중단). */}
                {isOwner && allPaymentsQ.isError && (
                  <div className="text-muted">결제 데이터 조회 실패 — 무결제 감시 일시 중단</div>
                )}
                {/* v1.5: 발급됐는데 결제 기록이 없는 active 회원권 — 추가 계약 모달의
                    "결제만 기록"으로 해소한다(owner 전용). */}
                {isOwner && unrecordedPasses.length > 0 && (
                  <div className="text-warn">
                    결제 기록 없는 회원권 <b>{unrecordedPasses.length}건</b> (
                    {unrecordedPasses.slice(0, 3).map((r, i) => (
                      <span key={r.pass.id}>
                        {i > 0 && "·"}
                        <NameLink
                          name={r.member.name}
                          onClick={onOpenMember && (() => onOpenMember(r.member.id))}
                        />
                      </span>
                    ))}
                    ) — 회원 상세에서 결제만 기록
                  </div>
                )}
                {todo.consentPending.length > 0 && (
                  <div>
                    동의 미완료 <b>{todo.consentPending.length}건</b> (
                    {todo.consentPending.slice(0, 3).map((m, i) => (
                      <span key={m.id}>
                        {i > 0 && "·"}
                        <NameLink name={m.name} onClick={onOpenMember && (() => onOpenMember(m.id))} />
                      </span>
                    ))}
                    )
                  </div>
                )}
                {todo.expiringSoon.length > 0 && (
                  <div>
                    회원권 만료 임박 <b>{todo.expiringSoon.length}명</b> (D-{expiringDays}) — 연장
                    제안
                  </div>
                )}
                {todo.lowRemaining.length > 0 && (
                  <div>
                    잔여 3회 미만 <b>{todo.lowRemaining.length}명</b> (
                    {todo.lowRemaining.slice(0, 2).map((r, i) => (
                      <span key={r.pass.id}>
                        {i > 0 && "·"}
                        <NameLink
                          name={r.member.name}
                          onClick={onOpenMember && (() => onOpenMember(r.member.id))}
                        />{" "}
                        {r.pass.remaining}회
                      </span>
                    ))}
                    ) — 재계약 상담
                  </div>
                )}
                {todo.longAbsent.length > 0 && (
                  <div className="text-danger">
                    장기 미출석{" "}
                    {todo.longAbsent.map((m, i) => (
                      <span key={m.id}>
                        {i > 0 && "·"}
                        <NameLink name={m.name} onClick={onOpenMember && (() => onOpenMember(m.id))} />
                      </span>
                    ))}{" "}
                    — 안부 메시지
                  </div>
                )}
                {!(isOwner && pendingJoinCount > 0) &&
                  // 가입 요청 조회 실패 중엔 "항목 없음"을 단정하지 않는다(대기 건수를 모름).
                  !(isOwner && joinReqQ.isError) &&
                  !pendingConsults.length &&
                  // 재등록 요청 조회 실패 중에도 "항목 없음"을 단정하지 않는다.
                  !consultQ.isError &&
                  !pendingContractsCount &&
                  !(isOwner && unpaidCount > 0) &&
                  // 결제 조회 실패 중엔 "항목 없음"을 단정하지 않는다(무결제 감시 결과를 모름).
                  !(isOwner && allPaymentsQ.isError) &&
                  !unrecordedPasses.length &&
                  !todo.consentPending.length &&
                  !todo.expiringSoon.length &&
                  !todo.lowRemaining.length &&
                  !todo.longAbsent.length && <div className="text-muted">오늘은 처리할 항목이 없습니다.</div>}
              </div>
            )}

            <Card className="mt-2.5 bg-panel-2">
              <CardContent className="pt-3.5">
                <div className="text-[11px] text-muted">이번 주 Home Work 완료율</div>
                <div className="mt-1 flex items-center gap-2.5">
                  {hwScopeStats.isError ? (
                    <span className="text-[12px] text-muted">— 통계를 불러오지 못했습니다</span>
                  ) : !hwView ? (
                    // 로딩 중을 0% 게이지로 그리지 않는다 — 아직 아무것도 모르는 화면이
                    // "완료 0%"를 확언하던 자리다.
                    <span className="text-[12px] text-muted">불러오는 중…</span>
                  ) : hwView.kind === "value" ? (
                    // 진짜 값. 분모가 양수라 0.0%도 여기로 온다(배정은 있는데 아무도 안 한 상태) —
                    // 그건 감출 일이 아니라 봐야 하는 숫자다.
                    <>
                      <ProgressBar className="flex-1" value={(hwView.rate ?? 0) * 100} />
                      <b className="text-[13px]">{hwView.text}</b>
                    </>
                  ) : (
                    // 게이지를 아예 그리지 않는다 — 텅 빈 막대는 "다 못 했다"로 읽히고 신규
                    // 센터에서는 그게 첫인상이 된다. 두 경우의 문구를 갈라 쓰는 것이 이번 수정의
                    // 핵심: hw_d === 0은 서버가 준 사실이라 건수를 그대로 말하고, hw_d 자체가
                    // 없는 응답(v2.1 이전 서버)에서는 "배정이 없어요"라고 단정하지 않는다.
                    <span className="text-[12px] text-muted">
                      {hwView.text}{" "}
                      {hwView.kind === "none"
                        ? "이번 주 집계 대상 0건"
                        : "완료율을 아직 알 수 없어요"}
                    </span>
                  )}
                </div>
              </CardContent>
            </Card>

            {!isOwner && (
              <>
                <Card className="mt-2 border-brand/30 bg-brand/[0.08]">
                  <CardContent className="pt-3.5">
                    <div className="text-[11px] text-muted">내 정산 ({myName || "-"})</div>
                    <TrainerPayoutLine
                      uid={me?.uid}
                      sessions={meStats.data?.sessions}
                      statsError={meStats.isError}
                    />
                  </CardContent>
                </Card>
                <Card className="mt-2">
                  <CardHeader>
                    <CardTitle className="text-[11px] font-normal text-muted">
                      내 통계 — 센터 평균과 비교 (타 코치 개별 수치는 비공개)
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    {meStats.isLoading || centerStats.isLoading ? (
                      <Spinner />
                    ) : meStats.isError || centerStats.isError ? (
                      <ErrorState error={meStats.error ?? centerStats.error} onRetry={() => { void meStats.refetch(); void centerStats.refetch(); }} />
                    ) : (
                      <Table>
                        <tbody>
                          <CompareRow
                            label="내 재등록률"
                            mine={meStats.data?.rereg_rate}
                            mineD={meStats.data?.rereg_d}
                            avg={centerStats.data?.rereg_rate}
                            avgD={centerStats.data?.rereg_d}
                            detail={
                              meStats.data?.rereg_d
                                ? `${meStats.data.rereg_n}/${meStats.data.rereg_d}`
                                : undefined
                            }
                          />
                          {/* 계약 v2.1로 노쇼·HW도 분모가 실린다 — 담당 수업이 아직 없는
                              신규 코치의 "노쇼율 0%(잘함)·HW 0%(못함)"라는 정반대 오독을
                              둘 다 "—"로 막는다. 진짜 0%는 분모가 양수라 그대로 표시된다. */}
                          <CompareRow
                            label="내 노쇼율"
                            mine={meStats.data?.noshow_rate}
                            mineD={meStats.data?.noshow_d}
                            avg={centerStats.data?.noshow_rate}
                            avgD={centerStats.data?.noshow_d}
                            detail={
                              meStats.data?.noshow_d ? `${meStats.data.noshow_d}건 기준` : undefined
                            }
                            lowerIsBetter
                          />
                          <CompareRow
                            label="담당 HW 완료율"
                            mine={meStats.data?.hw_rate}
                            mineD={meStats.data?.hw_d}
                            avg={centerStats.data?.hw_rate}
                            avgD={centerStats.data?.hw_d}
                          />
                        </tbody>
                      </Table>
                    )}
                    {todo.lowRemaining.length + todo.expiringSoon.length > 0 && (
                      <p className="mt-2 text-[11.5px]">
                        {/* 재계약 상담 = 잔여 소진·만료 임박(동의 미완료는 별개 개념이라 섞지 않는다). */}
                        재계약 상담 대상:{" "}
                        <b>
                          {[
                            ...todo.lowRemaining.map((r) => r.member.name),
                            ...todo.expiringSoon.map((m) => m.name),
                          ]
                            .filter((v, i, arr) => arr.indexOf(v) === i)
                            .slice(0, 3)
                            .join(" · ")}
                        </b>
                      </p>
                    )}
                  </CardContent>
                </Card>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      {isLoading && (
        <p className="mt-2 text-center text-[10.5px] text-muted">
          {formatDateWithDow(today)} 데이터 불러오는 중…
        </p>
      )}
    </div>
  );
}

// "해야 할 일"의 인라인 링크 — 회원 이름은 회원 관리 탭의 해당 회원 상세로(v1.4 UX 여정 마감),
// 가입 요청 신청자 이름은 회원 관리 상단 큐의 그 행으로(P69). 콜백이 없으면(임베드·권한 없음)
// 일반 텍스트로 렌더링해 데드 버튼을 만들지 않는다.
function NameLink({ name, onClick }: { name: string; onClick?: () => void }) {
  if (!onClick) return <>{name}</>;
  return (
    <button
      onClick={onClick}
      className="underline decoration-dotted underline-offset-2 transition hover:text-brand"
    >
      {name}
    </button>
  );
}

// 빈 센터 온보딩 한 단계. 탭 이동 콜백이 없으면(권한 없음) 버튼을 숨겨 데드 버튼을 만들지 않는다
// — 안내 문구 자체는 남겨 "무엇을 해야 하는지"는 그대로 전달한다.
function OnboardingStep({
  n,
  title,
  desc,
  actionLabel,
  onClick,
}: {
  n: number;
  title: string;
  desc: string;
  actionLabel: string;
  onClick?: () => void;
}) {
  return (
    <div className="rounded-[10px] border border-line bg-panel p-3">
      <div className="flex items-center gap-1.5">
        <span className="flex h-[17px] w-[17px] shrink-0 items-center justify-center rounded-full bg-brand text-[10px] font-black text-white">
          {n}
        </span>
        <b className="text-[12.5px]">{title}</b>
      </div>
      <div className="mt-1 text-[10.5px] leading-relaxed text-muted">{desc}</div>
      {onClick && (
        <Button variant="outline" size="sm" className="mt-2" onClick={onClick}>
          {actionLabel} <ArrowRight className="h-3 w-3" />
        </Button>
      )}
    </div>
  );
}

// 기준일 카피는 정책 실값(Dashboard에서 useCenter 파생값 전달) — 설정에서 바꾸면 여기도 따라온다.
function KpiCards({
  stats,
  reregWindowDays,
  longAbsentDays,
  expiringDays,
}: {
  stats: Stats;
  reregWindowDays: number;
  longAbsentDays: number;
  expiringDays: number;
}) {
  // 값도 설명문도 같은 3상태에서 갈라진다 — 값은 "—"인데 아래 설명만 "0명"이라 단정하는
  // 어긋남을 구조적으로 막는다(format.ts ratioState).
  const rereg = ratioState(stats.rereg_rate, stats.rereg_d, 0);
  const items: { l: string; v: string; sub: string; d: string; danger?: boolean }[] = [
    { l: "활동 회원", v: `${stats.active_members}`, sub: `/ 등록 ${stats.registered}`, d: "유효 회원권 보유" },
    { l: "신규 등록 (누적)", v: `${stats.registered}명`, sub: "", d: "누적 등록 회원 수" },
    {
      l: "재등록률",
      // 분모 0(만료된 회원이 아직 없음) = 모수 없음이지 성과 0%가 아니다 — "—"로 구분한다.
      v: rereg.text,
      sub: "",
      d:
        rereg.kind === "value"
          ? `${stats.rereg_n}/${stats.rereg_d}명 · 만료 후 ${reregWindowDays}일 내`
          : rereg.kind === "none"
            ? `만료 회원 0명 · 만료 후 ${reregWindowDays}일 내 집계`
            : `만료 후 ${reregWindowDays}일 내 집계 — 집계 기준을 아직 받지 못했어요`,
    },
    { l: "미배정", v: `${stats.unassigned}명`, sub: "", d: "담당 트레이너 없음" },
    {
      l: "장기 미출석",
      v: `${stats.long_absent}명`,
      sub: "",
      d: `${longAbsentDays}일 이상`,
      danger: stats.long_absent > 0,
    },
    { l: "회원권 종료", v: `${stats.expiring}명`, sub: "", d: `임박 D-${expiringDays} 이내` },
  ];
  return (
    <>
      {items.map((it) => (
        <Card key={it.l}>
          <CardContent className="pt-3.5">
            <div className="text-[11px] text-muted">{it.l}</div>
            <div className={`my-0.5 text-[21px] font-black ${it.danger ? "text-danger" : ""}`}>
              {it.v} {it.sub && <span className="text-xs font-normal text-muted">{it.sub}</span>}
            </div>
            <div className="text-[10.5px] text-muted">{it.d}</div>
          </CardContent>
        </Card>
      ))}
    </>
  );
}

function CompareRow({
  label,
  mine,
  mineD,
  avg,
  avgD,
  detail,
  lowerIsBetter,
}: {
  label: string;
  mine: number | undefined;
  avg: number | undefined;
  /** 비율의 분모(rereg_d · noshow_d · hw_d — 계약 v2.1로 세 지표 모두 실린다).
   *  0(집계 대상 없음)도 생략(구버전 서버라 미상)도 값을 보여주지 않는다 — 종전엔 생략일 때
   *  값을 그대로 찍어, 같은 응답을 Sales는 "—"로 대시보드는 "0.0%"로 표시했다.
   *  판단은 format.ts ratioState 한 곳에만 있다. */
  mineD?: number;
  avgD?: number;
  detail?: string;
  lowerIsBetter?: boolean;
}) {
  // 분모가 없거나 0인 값으로는 화살표를 붙이지 않는다 — 없는 성과를 판정하게 된다.
  const mineView = ratioState(mine, mineD);
  const avgView = ratioState(avg, avgD);
  const m = mineView.rate;
  const a = avgView.rate;
  const better = m !== undefined && a !== undefined && (lowerIsBetter ? m < a : m > a);
  const worse = m !== undefined && a !== undefined && (lowerIsBetter ? m > a : m < a);
  return (
    <TR>
      <TD>{label}</TD>
      <TD>
        <b>{mineView.text}</b>{" "}
        {mineView.kind === "value" ? (
          detail && `(${detail})`
        ) : (
          // "—"만 있으면 대표·트레이너가 고장으로 읽는다. 왜 비어 있는지를 같은 자리에서 말하되
          // 미상일 때는 "없다"고 단정하지 않는다(문구는 ratioState가 상태별로 들고 있다).
          <span className="text-[10.5px] text-muted">{mineView.note}</span>
        )}
      </TD>
      <TD className={better ? "text-ok" : worse ? "text-danger" : "text-muted"}>
        평균 {avgView.text} {better ? "▲" : worse ? "▼" : ""}
      </TD>
    </TR>
  );
}

// sessions — v1.4 Stats.sessions(scope=me): 본인 완료 세션 수(정산 근거). 건당 정산은 여기서
// 바로 총액까지 계산해 보여준다(요율형은 매출 귀속 규칙이 정산 화면 몫이라 세션 수만).
function TrainerPayoutLine({
  uid,
  sessions,
  statsError,
}: {
  uid: string | undefined;
  sessions: number | undefined;
  statsError?: boolean;
}) {
  const staffQ = useStaff();
  const mine = staffQ.data?.find((s) => s.uid === uid);
  if (staffQ.isLoading) return <Spinner />;
  if (staffQ.isError)
    return <div className="text-[11px] text-muted">정산 정보를 불러오지 못했습니다 — 새로고침해주세요.</div>;
  if (!mine)
    return (
      <div className="text-[11px] text-muted">
        {/* 초대는 UserIndex→Staff 2단 쓰기라 중간 실패 시 이 상태에 도달할 수 있다.
            원인은 내부 사정이므로 사용자에겐 다음 행동만 알려준다. */}
        정산 정보를 준비 중이에요 — 계속 보이면 센터 대표에게 문의해주세요.
      </div>
    );
  return (
    <>
      <div className="my-0.5 text-[15px] font-black">
        {/* rate는 0~1 소수(계약 확정) — 직표시하면 100배 축소돼 보인다. */}
        {mine.payout.type === "per_session"
          ? `${formatCurrency(mine.payout.value)}/회`
          : `요율 ${formatPercent(mine.payout.value)}`}
      </div>
      <div className="text-[11px] text-muted">
        {sessions === undefined ? (
          // 통계 조회 실패를 "불러오는 중"으로 위장하지 않는다 — 영구 로딩처럼 보이는 침묵 실패 방지.
          statsError ? (
            "통계를 불러오지 못했어요 — 새로고침해주세요."
          ) : (
            "완료 세션 수를 불러오는 중이에요…"
          )
        ) : mine.payout.type === "per_session" ? (
          <>
            완료 세션 <b className="text-ink">{sessions}회</b> → 정산{" "}
            <b className="text-ink">{formatCurrency(mine.payout.value * sessions)}</b> (연 누적)
          </>
        ) : (
          <>
            완료 세션 <b className="text-ink">{sessions}회</b> (연 누적) — 요율형 정산액은 매출
            확정 후 계산됩니다.
          </>
        )}
      </div>
    </>
  );
}

// 만료 임박·장기 미출석 기준일은 센터 정책 실값을 받는다(잔여<3은 정책에 없는 화면 자체 기준이라 유지).
function computeTodo(
  members: MemberWithPasses[],
  { expiringDays, longAbsentDays }: { expiringDays: number; longAbsentDays: number },
) {
  // P40: 네 버킷(동의 미완·만료 임박·재계약 상담·장기 미출석) 모두 탈퇴 회원 제외 — 가명화가
  // Consent를 리셋해 "동의 미완료"에 영원히 남고(계정 파기로 재동의 자체가 불가능), 연장 제안·
  // 재계약 상담·안부 메시지도 보낼 상대가 없다(탈퇴는 패스를 안 건드려 active 패스·last_visit_at이
  // 그대로 남는다). 탈퇴 회원 잔여 회차의 실제 남은 행동은 환불 정산인데 그건 이 버킷들의
  // 문구가 아니다. 장부 의무가 탈퇴와 무관하게 남는 "결제 기록 없는 회원권" 감시(unrecordedPasses
  // — 이 함수 밖)는 계속 탈퇴 포함으로 센다(P40 결정).
  const actionable = members.filter((m) => m.status !== "withdrawn");
  const consentPending = actionable.filter((m) => !m.consent.general || !m.consent.sensitive);
  const expiringSoon = actionable.filter((m) =>
    m.passes.some((p) => p.status === "active" && withinDays(p.valid_until, expiringDays)),
  );
  const lowRemaining = actionable.flatMap((m) =>
    m.passes
      .filter((p) => p.status === "active" && p.remaining > 0 && p.remaining < 3)
      .map((pass) => ({ member: m, pass })),
  );
  const longAbsent = actionable.filter(
    (m) => m.last_visit_at && daysSinceSafe(m.last_visit_at) >= longAbsentDays,
  );
  return { consentPending, expiringSoon, lowRemaining, longAbsent };
}

function withinDays(dateStr: string, days: number): boolean {
  const target = new Date(dateStr + "T00:00:00").getTime();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const diff = Math.round((target - today.getTime()) / 86_400_000);
  return diff >= 0 && diff <= days;
}

function daysSinceSafe(dateStr: string): number {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return 0;
  const today = new Date();
  return Math.round((today.getTime() - d.getTime()) / 86_400_000);
}
