// 회원 관리 — 목업 s-members 1:1(목록 + 상세 패널). 트레이너는 백엔드가 이미 담당만 스코프해
// 응답하므로(API계약: "역할 스코프 자동"), 화면은 트레이너 필터·검색을 모두 클라이언트에서 처리한다.
// "계약·결제" 섹션은 v1.1 정합 패치(Contract 엔티티 + GET /v1/payments?member=)로 실데이터 연동한다.
import { useMemo, useState } from "react";
import {
  Calculator,
  Check,
  CreditCard,
  Dumbbell,
  FileSignature,
  Pause,
  Pencil,
  Play,
  Plus,
  Send,
  Undo2,
  UserPlus,
} from "lucide-react";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Chip,
  EmptyState,
  ErrorState,
  Input,
  Label,
  Modal,
  Select,
  Spinner,
  TD,
  TH,
  THead,
  TR,
  Table,
  Textarea,
} from "@/components/ui";
import { useAuth } from "@/lib/auth";
import {
  useContracts,
  useCreateMember,
  useCreatePass,
  useCreatePayment,
  useHoldPass,
  useMemberLedger,
  useMembers,
  usePayInstallment,
  usePayments,
  useRefundPass,
  useRefundQuote,
  useResumePass,
  useSendContract,
  useStaff,
  useUpdateMember,
  useWorkoutLogs,
} from "@/lib/queries";
import {
  addDays,
  formatCurrency,
  formatPercent,
  isStaffActive,
  staffLabel,
  todayStr,
} from "@/lib/format";
import {
  CHANNEL_OPTIONS,
  type Contract,
  type LedgerReason,
  type Member,
  type MemberStatus,
  type MemberWithPasses,
  type Pass,
  type Payment,
  type Staff,
  isPassBookable,
} from "@/lib/types";

const LEDGER_LABEL: Record<LedgerReason, string> = {
  issue: "발급",
  complete: "수업 완료",
  noshow: "노쇼",
  noshow_waived: "노쇼 · 유예",
  revert: "취소 복구",
  refund: "환불",
  hold: "일시정지",
  resume: "재개",
  transfer: "담당 이관",
};

// focusMemberId — 대시보드 "해야 할 일"의 회원 이름 클릭 → 이 회원을 초기 선택(v1.4).
// 섹션 전환 시 App이 이 컴포넌트를 리마운트하므로 초기값으로만 써도 안전하다.
/// 회원 상태 표기. 종전엔 삼항 하나로 "활성/휴면"만 갈랐는데, v2.11의 withdrawn이 그 else에
/// 걸려 **탈퇴 회원이 "휴면"으로 표시**됐다 — 다시 부를 수 있는 사람처럼 보이는 거짓말이다.
/// 미지 값은 라벨을 지어내지 않되 원문(`suspended`)을 배지에 박지도 않는다 — 아래 UNKNOWN_LABEL.
const MEMBER_STATUS_LABEL: Record<string, string> = {
  active: "활성",
  dormant: "휴면",
  withdrawn: "탈퇴",
};
const MEMBER_STATUS_TONE: Record<string, "ok" | "muted" | "danger"> = {
  active: "ok",
  dormant: "muted",
  withdrawn: "danger",
};

/// 라벨을 못 찾은 상태 값 자리. 원문(`suspended`·`medical`)을 그대로 띄우면 한글 배지 안에
/// 영어 코드가 박혀 대표는 그것이 상태 이름인지 고장인지 알 수 없다 — 사람 말로 "확인 필요"라
/// 쓰고, 원문은 툴팁(title)에만 남겨 문의할 때 짚을 수 있게 한다.
const UNKNOWN_LABEL = "확인 필요";

/// 이름을 못 푼 담당 자리 — **raw uid는 어떤 경우에도 노출하지 않는다**(Schedule.tsx가 세운
/// 규약: `8fKq2xVnRZ…`는 사람이 읽을 정보가 아니고, "이름을 못 풀었다"와 "그런 이름이다"를
/// 구분할 수 없게 만든다). format.ts는 이 화면의 소관이 아니라 같은 문자열을 여기 둔다 —
/// 두 곳을 함께 고쳐야 하는 값이므로 옮길 일이 생기면 Schedule.tsx와 같이 옮긴다.
const UNRESOLVED_STAFF = "(담당 미확인)";

export function Members({ focusMemberId }: { focusMemberId?: string | null }) {
  const { me } = useAuth();
  const isOwner = me?.role === "owner";
  const membersQ = useMembers();
  const staffQ = useStaff();

  const [trainerFilter, setTrainerFilter] = useState<string>("all");
  const [q, setQ] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(focusMemberId ?? null);
  const [formOpen, setFormOpen] = useState<"create" | Member | null>(null);

  const filtered = useMemo(() => {
    let list = membersQ.data ?? [];
    // 탈퇴 회원은 기본 목록에서 뺀다(계약 v2.11). 서버는 계속 내려준다 — 5년 보존해야 하는
    // 계약·결제·원장이 member_id로 이 문서를 조인하기 때문이고, 지우면 미수금 표·계약 목록의
    // 이름 자리가 원시 ID로 깨진다. 그래서 **숨기는 건 클라이언트 몫**이다(v2.0 퇴사 스태프와
    // 같은 규약). 다만 완전히 감추지는 않는다: 보존 기록의 주인을 확인해야 하는 일이 실제로
    // 생기므로 전용 칩으로 꺼내 볼 수 있게 한다.
    list = trainerFilter === "withdrawn"
      ? list.filter((m) => m.status === "withdrawn")
      : list.filter((m) => m.status !== "withdrawn");
    if (trainerFilter === "unassigned") list = list.filter((m) => !m.trainer_id);
    else if (trainerFilter !== "all" && trainerFilter !== "withdrawn") {
      list = list.filter((m) => m.trainer_id === trainerFilter);
    }
    if (q.trim()) {
      const needle = q.trim().toLowerCase();
      // 전화번호는 **양쪽 다 숫자만 남겨** 비교한다. 종전엔 저장값(010-1234-5678)에
      // 입력값(01012345678)을 그대로 includes해서 "없음"이 떴고, 그 결과 이미 있는 회원을
      // 새로 등록하는 중복이 생겼다 — 번호는 앱 자동 매칭(P48)의 키라 중복이 특히 아프다.
      const digits = needle.replace(/[^0-9]/g, "");
      list = list.filter(
        (m) =>
          m.name.toLowerCase().includes(needle) ||
          (digits !== "" && m.phone.replace(/[^0-9]/g, "").includes(digits)),
      );
    }
    return list;
  }, [membersQ.data, trainerFilter, q]);

  // 상세는 **왼쪽 목록에 실제로 보이는 회원만** 띄운다. 종전엔 전체 목록에서 한 번 더 찾아
  // 폴백해서, 필터·검색을 바꿔 목록에서 사라진 회원의 상세가 오른쪽에 그대로 남았다 —
  // 하이라이트된 행이 어디에도 없는 "유령 상세"라 지금 무엇을 보고 있는지 알 수 없었다.
  const selected = filtered.find((m) => m.id === selectedId) ?? null;
  // 그렇다고 선택을 조용히 버리지도 않는다: selectedId는 그대로 둬서 필터를 되돌리면 상세가
  // 다시 열리고, 그 사이에는 "왜 사라졌는지 + 되찾는 법"을 상세 자리에 남긴다.
  const hiddenSelected =
    !selected && selectedId
      ? ((membersQ.data ?? []).find((m) => m.id === selectedId) ?? null)
      : null;
  // 담당 필터 칩 — **재직자만** 새로 고를 수 있다(v2.0: GET /v1/staff는 inactive도 준다).
  // 다만 이미 그 사람으로 필터가 걸린 상태에서 퇴사 처리가 들어오면 칩이 사라져 "왜 목록이
  // 비었는지" 알 수 없어지므로, 선택 중인 퇴사자 칩은 "(퇴사)" 표기로 남겨 해제할 수 있게 한다.
  const trainers = (staffQ.data ?? []).filter(
    (s) => (isOwner || s.uid === me?.uid) && (isStaffActive(s) || s.uid === trainerFilter),
  );
  // 미배정 카운트에서 탈퇴자를 뺀다 — 가명화가 trainer_id를 ""로 회수하므로(계약 v2.11),
  // 거르지 않으면 탈퇴자 전원이 "담당 배정이 필요한 회원"으로 잡혀 영원히 줄지 않는 할 일이 된다.
  // 서버 stats.unassigned도 같은 이유로 탈퇴자를 제외한다(두 숫자가 갈리면 안 된다).
  const unassignedCount = (membersQ.data ?? []).filter(
    (m) => !m.trainer_id && m.status !== "withdrawn",
  ).length;
  const activeCount = (membersQ.data ?? []).filter((m) => m.status === "active").length;
  const withdrawnCount = (membersQ.data ?? []).filter((m) => m.status === "withdrawn").length;

  return (
    <div>
      <h2 className="text-[16.5px] font-bold">회원 관리</h2>
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        {isOwner
          ? "회원권은 트레이너에게 묶입니다 — 담당별 필터, 회원권·원장까지 확인할 수 있습니다."
          : "내 담당 회원만 표시됩니다 — 다른 코치의 회원은 이 목록에 나오지 않습니다."}
      </p>

      <div className="grid gap-3 lg:grid-cols-[3fr_2fr]">
        <Card>
          <CardHeader>
            <CardTitle>
              회원 {membersQ.data?.length ?? 0}명 (활동 {activeCount})
            </CardTitle>
            <Button size="sm" onClick={() => setFormOpen("create")}>
              <UserPlus className="h-3.5 w-3.5" /> 등록
            </Button>
          </CardHeader>
          <CardContent>
            <div className="mb-2 flex flex-wrap items-center gap-2">
              <Input
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="이름·전화번호 검색"
                className="max-w-[220px]"
              />
              <div>
                <Chip active={trainerFilter === "all"} onClick={() => setTrainerFilter("all")}>
                  전체
                </Chip>
                {trainers.map((t) => (
                  <Chip key={t.uid} active={trainerFilter === t.uid} onClick={() => setTrainerFilter(t.uid)}>
                    {staffLabel(t)}
                  </Chip>
                ))}
                {isOwner && (
                  <Chip active={trainerFilter === "unassigned"} onClick={() => setTrainerFilter("unassigned")}>
                    미배정 {unassignedCount}
                  </Chip>
                )}
                {/* 탈퇴자가 한 명도 없으면 칩 자체를 띄우지 않는다 — 늘 0으로 붙어 있으면
                    필터 줄만 길어지고 아무 정보도 주지 않는다. */}
                {isOwner && withdrawnCount > 0 && (
                  <Chip active={trainerFilter === "withdrawn"} onClick={() => setTrainerFilter("withdrawn")}>
                    탈퇴 {withdrawnCount}
                  </Chip>
                )}
              </div>
            </div>

            {/* 직원 조회 실패를 화면이 조용히 삼키면 **담당이 있는 회원이 전부 "미배정"으로
                뒤집힌다** — 대표의 자연스러운 다음 행동(전원 재배정)이 곧 잘못된 데이터 쓰기다.
                Schedule.tsx가 같은 이유로 세운 배너 규약: 목록은 그대로 두고 "지금 무엇을
                믿으면 안 되는지"와 "하지 말 것"을 한 줄로 못박는다. */}
            {staffQ.isError && (
              <p className="mb-2 rounded-[10px] border border-warn/40 bg-warn/[0.08] px-3 py-2 text-[11px] leading-relaxed text-warn">
                직원 목록을 불러오지 못했어요 — 담당 이름을 확인할 수 없어 "{UNRESOLVED_STAFF}"로
                표시되고, 위 담당 필터도 비어 있어요. <b>담당이 실제로 지워진 것은 아니니 지금
                재배정하지 마세요.</b> ({staffQ.error.message})
              </p>
            )}

            {membersQ.isLoading ? (
              <Spinner />
            ) : membersQ.isError ? (
              <ErrorState error={membersQ.error} onRetry={() => void membersQ.refetch()} />
            ) : !filtered.length ? (
              // 전체 0건과 필터 0건을 구분한다 — 회원이 아예 없는데 "조건에 맞는"이라고 하면
              // 필터를 잘못 걸었나 싶어 검색어만 지워보다 등록 버튼을 못 찾는다.
              <EmptyState>
                {membersQ.data?.length === 0
                  ? isOwner
                    ? '아직 등록된 회원이 없습니다 — 위 "등록" 버튼으로 첫 회원을 추가해보세요.'
                    : '담당 회원이 아직 없습니다 — 위 "등록" 버튼으로 직접 등록하거나 센터 대표에게 배정을 요청하세요.'
                  : "조건에 맞는 회원이 없습니다 — 검색어·담당 필터를 확인해주세요."}
              </EmptyState>
            ) : (
              <Table>
                <THead>
                  <TR>
                    <TH>이름</TH>
                    <TH>담당</TH>
                    <TH>회원권</TH>
                    <TH>상태</TH>
                  </TR>
                </THead>
                <tbody>
                  {filtered.map((m) => {
                    const trainer = (staffQ.data ?? []).find((s) => s.uid === m.trainer_id);
                    const primaryPass = m.passes.find((p) => p.status === "active") ?? m.passes[0];
                    return (
                      <TR
                        key={m.id}
                        tabIndex={0}
                        onClick={() => setSelectedId(m.id)}
                        onKeyDown={(e) => {
                          // 행 전체가 클릭 타겟이므로 키보드(Enter/Space)로도 선택 가능해야 한다.
                          if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault();
                            setSelectedId(m.id);
                          }
                        }}
                        className={`cursor-pointer ${selectedId === m.id ? "bg-brand/[0.06]" : "hover:bg-panel-2"}`}
                      >
                        <TD className="font-bold">
                          {m.name}
                          {m.flags.some((f) => f.type === "injury") && (
                            <Badge tone="danger" className="ml-1.5">
                              부상
                            </Badge>
                          )}
                        </TD>
                        <TD>
                          {/* 퇴사자여도 이름 해석은 유지한다 — 빼면 담당이 있는 회원이 "미배정"으로
                              거짓말한다(계약 v2.0). 대신 톤을 낮추고 "(퇴사)"를 붙인다.
                              담당이 **있는데** 이름을 못 푼 경우(직원 조회 실패·이관 드리프트)도
                              같은 거짓말이라 "미배정"과 갈라 쓴다 — 미배정은 "배정해야 할 일",
                              미확인은 "지금은 알 수 없음"으로 다음 행동이 정반대다. */}
                          {trainer ? (
                            <Badge tone={isStaffActive(trainer) ? "warn" : "muted"}>
                              {staffLabel(trainer)}
                            </Badge>
                          ) : m.trainer_id ? (
                            <span className="text-muted">
                              {staffQ.isLoading ? "…" : UNRESOLVED_STAFF}
                            </span>
                          ) : (
                            <span className="text-muted">미배정</span>
                          )}
                        </TD>
                        <TD>
                          {primaryPass ? `${primaryPass.product} 잔여 ${primaryPass.remaining}` : "—"}
                        </TD>
                        <TD>
                          <Badge tone={MEMBER_STATUS_TONE[m.status] ?? "muted"}>
                            {MEMBER_STATUS_LABEL[m.status] ?? (
                              <span title={m.status}>{UNKNOWN_LABEL}</span>
                            )}
                          </Badge>
                        </TD>
                      </TR>
                    );
                  })}
                </tbody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          {!selected ? (
            <CardContent className="pt-4">
              <EmptyState>
                {hiddenSelected ? (
                  <>
                    <b className="text-ink">{hiddenSelected.name}</b> 님은 지금 걸린 검색·담당
                    필터에 걸리지 않아 목록에서 빠졌어요.
                    <div className="mt-2.5">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          setQ("");
                          setTrainerFilter("all");
                        }}
                      >
                        필터 지우고 다시 보기
                      </Button>
                    </div>
                  </>
                ) : (
                  "왼쪽 목록에서 회원을 선택하세요."
                )}
              </EmptyState>
            </CardContent>
          ) : (
            <MemberDetail member={selected} isOwner={isOwner} onEdit={() => setFormOpen(selected)} />
          )}
        </Card>
      </div>

      {formOpen && (
        <MemberFormModal
          initial={formOpen === "create" ? undefined : formOpen}
          staff={staffQ.data ?? []}
          onClose={() => setFormOpen(null)}
        />
      )}
    </div>
  );
}

const isWithdrawn = (m: { status: MemberStatus }) => m.status === "withdrawn";

/// 탈퇴 회원 상세 상단의 고지. 대표가 이 화면에서 답을 얻어야 하는 질문은 둘이다:
/// **① 왜 이 사람이 아직 목록에 있나 ② 언제까지 있어야 하나.** 둘 다 적어 두지 않으면
/// "지워지지 않은 데이터"로 보여 콘솔에서 손으로 지우려는 시도로 이어진다 — 그 순간
/// 5년 보존해야 할 계약·결제 기록이 함께 사라진다.
function WithdrawnNotice({ withdrawnAt }: { withdrawnAt?: string | null }) {
  const at = withdrawnAt ? new Date(withdrawnAt) : null;
  const until = at ? new Date(at.getFullYear() + 5, at.getMonth(), at.getDate()) : null;
  const fmt = (d: Date) => `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  return (
    <div className="mb-2.5 rounded-lg border border-danger/35 bg-danger/10 px-3 py-2 text-[11.5px] leading-relaxed">
      <b>탈퇴한 회원입니다{at ? ` (${fmt(at)})` : ""}.</b> 이름·전화번호와 체형사진·인바디·수업기록은
      이미 파기됐습니다. 아래에 남은 회원권·결제·계약은 전자상거래법상 보존 의무(계약·대금결제 5년)에
      따라 {until ? `${fmt(until)}까지 ` : ""}비식별 상태로 보관되는 기록이며, 수정할 수 없습니다.
    </div>
  );
}

function MemberDetail({
  member,
  isOwner,
  onEdit,
}: {
  member: MemberWithPasses;
  isOwner: boolean;
  onEdit: () => void;
}) {
  const [ledgerPass, setLedgerPass] = useState<string>("");
  // 환불 대상은 **passId로만** 들고 매 렌더 다시 찾는다 — Pass 객체를 붙잡아두면 상담하는
  // 동안 다른 스태프가 수업을 완료했을 때 모달이 옛 used를 계속 보내 400만 반복된다
  // (서버는 used가 원장 파생값과 다르면 거부 — service.RefundPass).
  const [refundPassId, setRefundPassId] = useState<string | null>(null);
  const [holdTarget, setHoldTarget] = useState<Pass | null>(null);
  const [registerOpen, setRegisterOpen] = useState(false);
  // 납부 처리 2단 확인 — "{paymentId}:{index}". 서버에 납부 취소 동사가 없어 원클릭이면
  // 오클릭 한 번이 곧 완납 확정 + 미수금 KPI 오염이다(환불·고정 스케줄 삭제와 같은 무게).
  const [payConfirm, setPayConfirm] = useState<string | null>(null);
  const ledgerQ = useMemberLedger(member.id, ledgerPass || undefined);
  const contractsQ = useContracts(member.id);
  const paymentsQ = usePayments(member.id);
  const staffQ = useStaff();
  const resumePass = useResumePass();
  // P38: 발송 성공 표식(계약 id). sent_at이 일 단위 표시라 같은 날 재발송은 화면 무변화 →
  // "안 눌린 줄" 연타 → 회원에게 서명 요청 중복 발송이었다. 대시보드 체크인(checkedInIds)과
  // 같은 세션 로컬 표시 — 새로고침하면 사라지지만 연타 혼선은 막는다.
  // P40: 마킹은 mutate-레벨 옵션이 아니라 **훅-레벨 콜백**으로 — mutate-레벨 onSuccess는
  // 다른 계약을 이어서 발송하는 순간 옵저버가 떨어져 실행되지 않아(react-query v5), 앞선 건이
  // 성공하고도 "발송됨"을 얻지 못했다(연타 방지가 정확히 연속 발송에서 뚫리는 구멍).
  const [sentMarkIds, setSentMarkIds] = useState<Set<string>>(new Set());
  const sendContract = useSendContract((id) => setSentMarkIds((prev) => new Set(prev).add(id)));
  const payInstallment = usePayInstallment();

  // 기존 데이터 표시라 퇴사자도 계속 해석한다 — "(퇴사)"를 붙여 재배정 대상이 아님을 알린다.
  // 못 풀면 **uid를 그대로 흘리지 않는다**(Schedule.tsx 규약): `담당 t1`·`8fKq2xVnRZ…`는
  // 대표에게 아무 정보도 아니면서, 이름을 못 푼 것인지 그런 이름인지조차 알 수 없게 만든다.
  // 로딩 중과 미해석을 갈라 쓴다 — 아직 오지 않은 응답을 "확인 불가"로 단정하지 않는다.
  const staffName = (uid: string) => {
    const s = staffQ.data?.find((x) => x.uid === uid);
    if (s) return staffLabel(s);
    return staffQ.isLoading ? "…" : UNRESOLVED_STAFF;
  };

  // 민감정보 동의 철회 시각(계약 Consent.revoked_at). 어드민 전체에서 이 필드를 읽는 곳이
  // 체형 분석 화면 한 군데뿐이라, 철회한 회원도 이 화면에서는 초록 체크로 보였다 — 아래 배지가
  // 그 어긋남을 닫는다.
  const consentRevokedAt = member.consent.revoked_at;

  // passId → 지금 목록의 Pass. 캐시가 갱신되면(다른 스태프의 수업 완료 등) 모달이 곧바로
  // 새 remaining을 본다 — 스냅샷을 붙잡고 있으면 서버의 used 정합 검사에 계속 걸린다.
  const refundTarget = refundPassId
    ? (member.passes.find((p) => p.id === refundPassId) ?? null)
    : null;

  return (
    <>
      <CardHeader>
        <CardTitle>{member.name}</CardTitle>
        {/* 탈퇴 회원은 수정 버튼 자체를 없앤다 — 서버가 PUT을 400으로 막는다(v2.11:
            되살리기 차단). 버튼을 남겨두면 눌러보고서야 실패를 알게 되는데, 그 시도가
            "되살릴 수 있나?"라는 잘못된 기대를 먼저 만든다. */}
        {!isWithdrawn(member) && (
          <Button size="sm" variant="outline" onClick={onEdit}>
            <Pencil className="h-3.5 w-3.5" /> 수정
          </Button>
        )}
      </CardHeader>
      <CardContent>
        {isWithdrawn(member) && <WithdrawnNotice withdrawnAt={member.withdrawn_at} />}
        <div className="mb-2.5 text-[11.5px] text-muted">
          {member.phone} · 진입경로 {member.channel || "—"} ·{" "}
          {member.app_linked ? (
            <span className="inline-flex items-center gap-0.5 text-ok">
              앱 연결됨 <Check className="h-3 w-3" />
            </span>
          ) : (
            "앱 미연결"
          )}
          <br />
          담당{" "}
          {member.trainer_id ? (
            staffName(member.trainer_id)
          ) : (
            <span className="text-danger">미배정</span>
          )}
        </div>

        <div className="mb-1.5 flex flex-wrap gap-1.5">
          <Badge tone={member.consent.general ? "ok" : "muted"}>
            <span className="inline-flex items-center gap-0.5">
              일반 동의 {member.consent.general ? <Check className="h-3 w-3" /> : "미완료"}
            </span>
          </Badge>
          {/* **철회를 초록 체크로 덮지 않는다.** 종전엔 revoked_at을 보지 않아 철회한 회원도
              "민감정보 동의 ✓"였다 — 체형 분석 화면은 같은 회원을 잠근 채 "회원 관리에서 동의
              상태를 확인하세요"라고 보내는데, 와 보면 정반대를 말하는 화면이었다. */}
          <Badge
            tone={consentRevokedAt ? "danger" : member.consent.sensitive ? "ok" : "muted"}
          >
            <span className="inline-flex items-center gap-0.5">
              민감정보 동의{" "}
              {consentRevokedAt ? (
                "철회됨"
              ) : member.consent.sensitive ? (
                <Check className="h-3 w-3" />
              ) : (
                "미완료"
              )}
            </span>
          </Badge>
          {member.flags.map((f, i) => (
            <Badge key={i} tone="danger">
              {/* 미지 플래그 종류의 원문(`medical`)을 한글 배지 안에 박지 않는다 — 툴팁에만 남긴다. */}
              <span title={f.type === "injury" ? undefined : f.type}>
                {f.type === "injury" ? "부상" : UNKNOWN_LABEL}
                {f.note ? `: ${f.note}` : ""}
              </span>
            </Badge>
          ))}
        </div>
        {/* 배지 한 칸으로는 "그래서 뭘 해야 하나"에 답할 수 없다 — 이 잠금은 센터가 못 푼다는
            사실과, 사진이 지워진 게 아니라는 사실을 같은 자리에서 말한다(체형 분석 화면과 같은 말). */}
        {consentRevokedAt && (
          <p className="mb-1.5 text-[10.5px] leading-relaxed text-danger">
            {consentRevokedAt.slice(0, 10)} 철회 — 체형사진 촬영·열람이 잠겨 있어요.{" "}
            <b>회원이 앱 마이 탭의 "민감정보(인바디·체형사진) 동의"에서 다시 동의하면 바로 열려요(센터에서는 풀 수 없어요).</b> 이미 찍어 둔
            사진은 지워지지 않아요.
          </p>
        )}

        <div className="mb-1 mt-3 text-[11px] text-muted">
          회원권 {member.passes.length}개 — 트레이너별 바인딩
        </div>
        {!member.passes.length ? (
          <EmptyState>등록된 회원권이 없습니다.</EmptyState>
        ) : (
          <div className="space-y-1.5">
            {member.passes.map((p) => {
              // 홀딩 기간 판정은 active 패스에만 — 환불·만료된 패스가 과거 홀딩 이력 때문에
              // "일시정지 중" 배지·재개 버튼을 얻는 오표시를 막는다.
              const heldNow =
                p.status === "active" &&
                p.holds.some((h) => h.from <= todayStr() && todayStr() <= h.to);
              return (
                <Card key={p.id} className="bg-panel-2">
                  <CardContent className="pt-3">
                    <div className="flex flex-wrap items-center justify-between gap-1.5">
                      <b className="text-[12.5px]">
                        {p.product} · {staffName(p.trainer_id)}
                      </b>
                      <Badge
                        tone={
                          p.status === "active" ? "ok" : p.status === "scheduled" ? "blue" : p.status === "refunded" ? "danger" : "muted"
                        }
                      >
                        {heldNow ? (
                          "일시정지 중"
                        ) : (
                          PASS_STATUS_LABEL[p.status] ?? <span title={p.status}>{UNKNOWN_LABEL}</span>
                        )}
                      </Badge>
                    </div>
                    <div className="mt-0.5 text-[11px] text-muted">
                      {/* v1.5 어휘: paid_amount = 계약가(실수납은 결제 회차 합 paid_sum) — 라벨 통일. */}
                      잔여 {p.remaining}/{p.total_sessions}회 · ~{p.valid_until} · 계약가{" "}
                      {formatCurrency(p.paid_amount)}
                    </div>
                    {p.holds.length > 0 && (
                      <div className="mt-1 text-[10.5px] text-muted">
                        정지 이력 {p.holds.length}회:{" "}
                        {p.holds.map((h, i) => (
                          <span key={i} className="mr-1.5">
                            {h.from}~{h.to}({h.reason})
                          </span>
                        ))}
                      </div>
                    )}
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {heldNow ? (
                        <Button size="sm" variant="outline" onClick={() => resumePass.mutate(p.id)} disabled={resumePass.isPending}>
                          <Play className="h-3 w-3" /> 재개
                        </Button>
                      ) : (
                        p.status === "active" && (
                          <Button size="sm" variant="outline" onClick={() => setHoldTarget(p)}>
                            <Pause className="h-3 w-3" /> 일시정지
                          </Button>
                        )
                      )}
                      {/* 이미 환불된 패스는 재환불 대상이 아니다(서버도 400) — 진입 자체를 숨긴다. */}
                      {isOwner && p.status !== "refunded" && (
                        <Button size="sm" variant="outline" onClick={() => setRefundPassId(p.id)}>
                          <Calculator className="h-3 w-3" /> 환불 계산
                        </Button>
                      )}
                    </div>
                    {resumePass.isError && resumePass.variables === p.id && (
                      <p className="mt-1.5 text-[11px] text-danger">{resumePass.error.message}</p>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}

        <div className="mt-3 mb-1 flex items-center justify-between">
          <span className="text-[11px] text-muted">계약 · 결제</span>
          {/* P38: 탈퇴 회원에겐 추가 계약(재등록) 입구를 없앤다 — 서버가 400으로 거부한다
              (guardMemberNotWithdrawn). 눌러보고야 실패를 아는 버튼을 남기지 않는다(위 수정
              버튼 선례). 아래 계약·결제 목록은 5년 보존 기록 열람이라 그대로 남는다. */}
          {!isWithdrawn(member) && (
            <Button size="sm" onClick={() => setRegisterOpen(true)}>
              <Plus className="h-3.5 w-3.5" /> 추가 계약(재등록)
            </Button>
          )}
        </div>
        <div className="mb-1 flex items-center gap-1 text-[10.5px] text-muted">
          <FileSignature className="h-3 w-3" /> 계약 목록
        </div>
        {contractsQ.isLoading ? (
          <Spinner />
        ) : contractsQ.isError ? (
          <ErrorState error={contractsQ.error} onRetry={() => void contractsQ.refetch()} />
        ) : !contractsQ.data?.length ? (
          <EmptyState>등록된 계약이 없습니다.</EmptyState>
        ) : (
          <Table>
            <THead>
              <TR>
                <TH>상품</TH>
                <TH>상태</TH>
                <TH>발송 · 서명일</TH>
                <TH></TH>
              </TR>
            </THead>
            <tbody>
              {contractsQ.data.map((c) => {
                // P38: 진행·실패·발송됨은 **이 계약 행**만 본다(아래 payInstallment의 variables
                // 행 식별과 같은 패턴). 종전엔 isPending 하나로 모든 행 버튼이 함께 잠기고
                // 에러는 목록 아래 한 곳에 떠서 어느 계약의 실패인지 알 수 없었다.
                const isThis = sendContract.variables === c.id;
                const rowPending = sendContract.isPending && isThis;
                const rowFailed = sendContract.isError && isThis;
                const justSent = sentMarkIds.has(c.id);
                return (
                  <TR key={c.id}>
                    <TD className="font-bold">
                      {c.product}
                      <div className="text-[10.5px] font-normal text-muted">
                        {/* v1.5: 계약가 + 서명 요율 스냅샷(회원 동의 요율 — 정책 변경 비소급).
                            null = 레거시(v1.5 이전 — 스냅샷 없음, 정산 시 현재 정책 폴백) → "—",
                            0 = 회원이 동의한 0% → 그대로 % 표기(둘은 다른 상태). */}
                        {formatCurrency(c.paid_amount)} · 요율{" "}
                        {c.penalty_rate !== null ? formatPercent(c.penalty_rate) : "—"}
                      </div>
                    </TD>
                    <TD>
                      <Badge tone={contractStatusTone(c.status)}>
                        {CONTRACT_STATUS_LABEL[c.status] ?? (
                          <span title={c.status}>{UNKNOWN_LABEL}</span>
                        )}
                      </Badge>
                    </TD>
                    <TD
                      className="text-[11px] text-muted"
                      // v1.5: 최초 발송 증적(first_sent_at) — 재발송해도 지워지지 않는 최초 고지 시각.
                      title={c.first_sent_at ? `최초 발송 ${c.first_sent_at.slice(0, 10)}` : undefined}
                    >
                      발송 {c.sent_at ? c.sent_at.slice(0, 10) : "—"} · 서명{" "}
                      {c.signed_at ? c.signed_at.slice(0, 10) : "—"}
                      {c.first_sent_at && c.first_sent_at !== c.sent_at && (
                        <div className="text-[10px]">최초 발송 {c.first_sent_at.slice(0, 10)}</div>
                      )}
                    </TD>
                    <TD>
                      {/* 백엔드 POST /v1/contracts/{id}/send는 draft→sent 최초 발송도 허용 — draft에도 노출.
                          voided(환불·탈퇴 무효)·signed는 종단 상태 — 어떤 액션도 없다(재발송 400).
                          P40: 탈퇴는 남은 draft·sent 계약을 서버가 전부 void한다 — 탈퇴 회원의
                          계약은 종단 상태뿐이라 상태 게이트만으로도 버튼이 안 뜬다. isWithdrawn
                          숨김은 이중 방어(P38 선례). 목록 자체는 5년 보존 열람으로 유지. */}
                      {!isWithdrawn(member) && (c.status === "draft" || c.status === "sent") && (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={rowPending || justSent}
                          onClick={() => sendContract.mutate(c.id)}
                        >
                          {justSent ? <Check className="h-3 w-3" /> : <Send className="h-3 w-3" />}{" "}
                          {rowPending
                            ? "발송 중…"
                            : justSent
                              ? "발송됨"
                              : c.status === "sent"
                                ? "재발송"
                                : "발송"}
                        </Button>
                      )}
                      {rowFailed && (
                        <p className="mt-1 text-[10.5px] text-danger">
                          발송 실패: {sendContract.error.message}
                        </p>
                      )}
                    </TD>
                  </TR>
                );
              })}
            </tbody>
          </Table>
        )}
        {/* 발송 실패는 실패한 계약 행 안에 붙인다(위 rowFailed) — 목록 아래 한 곳이면 계약이
            여러 건일 때 무엇이 실패했는지 알 수 없다(회차 납부 에러와 같은 원칙). */}

        <div className="mt-2.5 mb-1 flex items-center gap-1 text-[10.5px] text-muted">
          <CreditCard className="h-3 w-3" /> 결제 목록
        </div>
        {paymentsQ.isLoading ? (
          <Spinner />
        ) : paymentsQ.isError ? (
          <ErrorState error={paymentsQ.error} onRetry={() => void paymentsQ.refetch()} />
        ) : !paymentsQ.data?.length ? (
          <EmptyState>결제 기록이 없습니다.</EmptyState>
        ) : (
          <div className="space-y-1.5">
            {paymentsQ.data.map((pay) => {
              // v1.5 회차 상태 4분류: 납부완료(paid_at) / 청구 종결(waived_at — 환불로 정산 종료) /
              // 연체(미납·due<오늘 — due 당일은 아직 연체 아님, 서버 규약 동일) / 예정(미납·due≥오늘).
              const today = todayStr();
              const open = pay.installments.filter((inst) => !inst.paid_at && !inst.waived_at);
              const overdueCount = open.filter((inst) => inst.due < today).length;
              const upcomingCount = open.length - overdueCount;
              const passRefunded =
                member.passes.find((p) => p.id === pay.pass_id)?.status === "refunded";
              return (
                <Card key={pay.id} className="bg-panel-2">
                  <CardContent className="pt-3">
                    <div className="flex flex-wrap items-center justify-between gap-1.5">
                      <b className="text-[12.5px]">
                        {PAYMENT_METHOD_LABEL[pay.method]} · {formatCurrency(pay.total)}
                      </b>
                      <span className="flex flex-wrap gap-1">
                        {overdueCount > 0 && <Badge tone="danger">연체 {overdueCount}건</Badge>}
                        {upcomingCount > 0 && <Badge tone="muted">예정 {upcomingCount}건</Badge>}
                      </span>
                    </div>
                    {passRefunded && (
                      <p className="mt-1 text-[10.5px] text-muted">
                        환불로 정산 종결 — 미납 회차는 청구 종결 처리돼 더 이상 수납하지 않아요.
                      </p>
                    )}
                    {pay.installments.length > 0 && (
                      <div className="mt-1.5 space-y-1">
                        {pay.installments.map((inst, i) => {
                          const waived = !!inst.waived_at;
                          const overdue = !inst.paid_at && !waived && inst.due < today;
                          const payable = !inst.paid_at && !waived; // 예정 회차도 조기 납부 가능
                          const rowKey = `${pay.id}:${i}`;
                          // 진행/실패는 **이 회차**만 본다. 종전엔 isPending 하나로 그 회원의 모든
                          // 회차 버튼이 함께 잠기고 에러는 목록 맨 아래 한 곳에만 떠서, 어느 회차가
                          // 실패했는지 알 수 없었다(variables로 대상 회차를 식별한다).
                          const isThis =
                            payInstallment.variables?.paymentId === pay.id &&
                            payInstallment.variables?.index === i;
                          const rowPending = payInstallment.isPending && isThis;
                          const rowFailed = payInstallment.isError && isThis;
                          return (
                            <div key={i}>
                              <div className="flex flex-wrap items-center justify-between gap-1.5 text-[11.5px]">
                                <span className={overdue ? "font-bold text-danger" : "text-muted"}>
                                  {i + 1}회차 {formatCurrency(inst.amount)} · 납부기한 {inst.due}
                                  {inst.paid_at
                                    ? ` · 완납 ${inst.paid_at.slice(0, 10)}`
                                    : waived
                                      ? " · 환불 종결"
                                      : overdue
                                        ? " · 연체"
                                        : " · 예정"}
                                </span>
                                {/* 청구 종결(waived) 회차는 납부 버튼 없음 — 서버도 400으로 거부. */}
                                {payable && payConfirm !== rowKey && (
                                  <Button
                                    size="sm"
                                    disabled={rowPending}
                                    onClick={() => setPayConfirm(rowKey)}
                                  >
                                    <Check className="h-3 w-3" /> 납부 처리
                                  </Button>
                                )}
                              </div>
                              {payable && payConfirm === rowKey && (
                                <div className="mt-1.5 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-2.5">
                                  <p className="text-[11px] leading-relaxed text-danger">
                                    {i + 1}회차 {formatCurrency(inst.amount)}을(를) 완납으로
                                    기록합니다. 납부를 취소하는 기능이 없어 되돌릴 수 없고, 미수금
                                    집계에서 즉시 빠져요.
                                  </p>
                                  <div className="mt-1.5 flex gap-1.5">
                                    <Button
                                      size="sm"
                                      variant="danger"
                                      disabled={rowPending}
                                      onClick={() =>
                                        payInstallment.mutate(
                                          { paymentId: pay.id, index: i },
                                          { onSuccess: () => setPayConfirm(null) },
                                        )
                                      }
                                    >
                                      {rowPending ? "처리 중…" : "납부 확정"}
                                    </Button>
                                    <Button
                                      size="sm"
                                      variant="ghost"
                                      disabled={rowPending}
                                      onClick={() => setPayConfirm(null)}
                                    >
                                      취소
                                    </Button>
                                  </div>
                                </div>
                              )}
                              {rowFailed && (
                                <p className="mt-1 text-[10.5px] text-danger">
                                  {i + 1}회차 납부 처리 실패: {payInstallment.error.message}
                                </p>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
        {/* 납부 실패는 실패한 회차 바로 아래에 붙인다(위 rowFailed) — 목록 맨 아래 한 곳에
            모아두면 회차가 여러 개일 때 무엇이 실패했는지 알 수 없다. */}

        <div className="mt-3 mb-1 flex items-center justify-between">
          <span className="text-[11px] text-muted">세션 원장</span>
          {member.passes.length > 1 && (
            <Select value={ledgerPass} onChange={(e) => setLedgerPass(e.target.value)} className="w-auto text-[11px]">
              <option value="">전체 회원권</option>
              {member.passes.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.product}
                </option>
              ))}
            </Select>
          )}
        </div>
        {ledgerQ.isLoading ? (
          <Spinner />
        ) : ledgerQ.isError ? (
          <ErrorState error={ledgerQ.error} onRetry={() => void ledgerQ.refetch()} />
        ) : !ledgerQ.data?.length ? (
          <EmptyState>원장 기록이 없습니다.</EmptyState>
        ) : (
          <Table>
            <tbody>
              {ledgerQ.data.map((l) => (
                <TR key={l.id}>
                  <TD className="text-muted">{l.at.slice(0, 10)}</TD>
                  <TD>{LEDGER_LABEL[l.reason]}</TD>
                  <TD className={l.delta < 0 ? "text-danger" : l.delta > 0 ? "text-ok" : "text-muted"}>
                    {l.delta > 0 ? "+" : ""}
                    {l.delta}
                  </TD>
                </TR>
              ))}
            </tbody>
          </Table>
        )}

        <WorkoutLogSection memberId={member.id} staffName={staffName} />
      </CardContent>

      {holdTarget && <HoldModal pass={holdTarget} onClose={() => setHoldTarget(null)} />}
      {refundPassId &&
        (refundTarget ? (
          <RefundQuoteModal pass={refundTarget} onClose={() => setRefundPassId(null)} />
        ) : (
          // 목록에서 사라진 회원권(다른 창에서 처리됨 등) — 조용히 닫지 않고 이유를 남긴다.
          <Modal open onClose={() => setRefundPassId(null)} title="환불 계산기">
            <div className="space-y-3">
              <p className="text-[12.5px] text-warn">
                이 회원권을 목록에서 찾을 수 없어요 — 그 사이에 목록이 갱신됐을 수 있어요. 창을
                닫고 회원권을 다시 선택해주세요.
              </p>
              <Button className="w-full" onClick={() => setRefundPassId(null)}>
                닫기
              </Button>
            </div>
          </Modal>
        ))}
      {registerOpen && (
        <AddContractModal member={member} staff={staffQ.data ?? []} onClose={() => setRegisterOpen(false)} />
      )}
    </>
  );
}

// 수업 기록(WorkoutLog, v1.4) — 트레이너가 완료 처리 직후 남긴 30초 기록(P29)을 회원 상세에서
// 최신순으로 본다(회원 앱 "기록" 탭과 같은 데이터). 입력은 예약 화면 완료 처리 모달에서.
function WorkoutLogSection({
  memberId,
  staffName,
}: {
  memberId: string;
  staffName: (uid: string) => string;
}) {
  const logsQ = useWorkoutLogs(memberId);
  const logs = useMemo(
    () => [...(logsQ.data ?? [])].sort((a, b) => b.date.localeCompare(a.date)),
    [logsQ.data],
  );
  return (
    <>
      <div className="mt-3 mb-1 flex items-center gap-1 text-[11px] text-muted">
        <Dumbbell className="h-3 w-3" /> 수업 기록
      </div>
      {logsQ.isLoading ? (
        <Spinner />
      ) : logsQ.isError ? (
        <ErrorState error={logsQ.error} onRetry={() => void logsQ.refetch()} />
      ) : !logs.length ? (
        <EmptyState>수업 기록이 없습니다 — 예약 완료 처리 직후 30초 기록으로 남길 수 있어요.</EmptyState>
      ) : (
        <div className="space-y-1.5">
          {logs.map((log) => (
            <Card key={log.id} className="bg-panel-2">
              <CardContent className="pt-3">
                <div className="flex flex-wrap items-center justify-between gap-1.5">
                  <b className="text-[12.5px]">
                    {log.date} · {log.title}
                  </b>
                  <span className="text-[10.5px] text-muted">{staffName(log.trainer_id)}</span>
                </div>
                {log.exercises.length > 0 && (
                  <div className="mt-1 space-y-0.5 text-[11.5px]">
                    {log.exercises.map((ex, i) => (
                      <div key={i}>
                        {ex.name}{" "}
                        <span className="text-muted">
                          {ex.sets > 0 ? `${ex.sets}×${ex.reps}` : ex.reps}
                          {ex.weight_kg > 0 ? ` · ${ex.weight_kg}kg` : ""}
                        </span>
                        {ex.note && <span className="text-[10.5px] text-muted"> — {ex.note}</span>}
                      </div>
                    ))}
                  </div>
                )}
                {log.coach_note && (
                  <div className="mt-1 text-[11px] text-muted">코치 코멘트: {log.coach_note}</div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </>
  );
}

/// 미지 상태는 라벨을 지어내지 않되 원문을 배지에 박지도 않는다(UNKNOWN_LABEL + 툴팁).
/// union 키(Record<Pass["status"], …>)로 좁혀 두면 서버가 새 상태를 먼저 배포한 구간에
/// 빈 배지가 렌더되므로 키 타입은 string으로 열어 둔다.
const PASS_STATUS_LABEL: Record<string, string> = {
  active: "활성",
  scheduled: "시작 예정",
  expired: "만료",
  refunded: "환불됨",
};

/// 미지 상태는 라벨을 지어내지 않되 원문을 배지에 박지도 않는다(UNKNOWN_LABEL + 툴팁).
/// union 키로 좁히면 새 상태가 빈 배지로 렌더되므로 키 타입은 string으로 열어 둔다.
const CONTRACT_STATUS_LABEL: Record<string, string> = {
  draft: "초안",
  sent: "서명 대기",
  signed: "서명완료",
  // v1.5: 패스 환불로 거래가 해지돼 서명 대상에서 빠진 계약(종단) — 액션 없음.
  voided: "무효(환불)",
};

// Badge의 tone prop 타입은 export되지 않아(components/ui.tsx) 다른 화면과 동일하게 리터럴을 직접 반환한다.
function contractStatusTone(status: Contract["status"]): "muted" | "warn" | "ok" {
  if (status === "signed") return "ok";
  if (status === "sent") return "warn";
  return "muted"; // draft · voided(무효)
}

const PAYMENT_METHOD_LABEL: Record<Payment["method"], string> = {
  card: "카드",
  cash: "현금",
  transfer: "계좌이체",
};

function HoldModal({ pass, onClose }: { pass: Pass; onClose: () => void }) {
  const [from, setFrom] = useState(todayStr());
  const [to, setTo] = useState(todayStr());
  const [reason, setReason] = useState("");
  const holdPass = useHoldPass();

  return (
    <Modal open onClose={onClose} title={`일시정지 — ${pass.product}`}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-2">
          <div>
            <Label>시작일</Label>
            <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div>
            <Label>종료일</Label>
            <Input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} />
          </div>
        </div>
        <div>
          <Label>사유</Label>
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="여행, 부상 등" />
        </div>
        {to && from && to < from && (
          <p className="text-[11px] text-warn">종료일은 시작일 이후여야 해요.</p>
        )}
        {holdPass.isError && <p className="text-[11px] text-danger">{holdPass.error.message}</p>}
        <Button
          className="w-full"
          disabled={!from || !to || to < from || holdPass.isPending}
          onClick={() => holdPass.mutate({ id: pass.id, body: { from, to, reason } }, { onSuccess: onClose })}
        >
          <Pause className="h-4 w-4" /> 정지 적용
        </Button>
        <p className="text-[10.5px] text-muted">
          정지 기간만큼 회원권 유효기간이 자동 연장됩니다(정책: 최대 횟수·총 일수는 설정 화면 참고).
        </p>
      </div>
    </Modal>
  );
}

// v1.4: 견적(refund-quote) 아래에 환불 "실행"(POST /v1/passes/{id}/refund)까지 — owner 전용,
// 2단 확인 후 원장 refund(잔여 0 마감) + status=refunded 전이. 이미 refunded면 서버가 400.
function RefundQuoteModal({ pass, onClose }: { pass: Pass; onClose: () => void }) {
  const { me } = useAuth();
  const isOwner = me?.role === "owner";
  // used는 원장 파생값(총 − 잔여)으로 고정 — 서버도 이 값과 다른 used를 400으로 거부한다
  // (정합 규칙). what-if 실험은 매출·통계의 정책 계산기 몫.
  const used = pass.total_sessions - pass.remaining;
  const [confirming, setConfirming] = useState(false);
  const refundQuote = useRefundQuote();
  const refundPass = useRefundPass();
  // 견적을 낸 뒤 원장이 움직였는지(상담 중 다른 스태프가 수업을 완료·노쇼 처리). pass가 이제
  // 매 렌더 재조회되므로 used는 최신인데 견적은 옛 값 기준이다 — 그대로 실행하면 서버가
  // "사용 횟수가 원장과 달라요" 400을 내고 모달 안에서는 원인도 복구 경로도 보이지 않는다.
  const quoteStale = refundQuote.isSuccess && refundQuote.variables?.used !== used;

  // 환불 완료 — 결과만 보여주고 닫는다(입력 UI로 되돌아갈 이유가 없음).
  if (refundPass.isSuccess) {
    return (
      <Modal open onClose={onClose} title={`환불 처리 — ${pass.product}`}>
        <div className="space-y-3">
          <p className="text-[13px] font-bold text-ok">
            <Check className="mr-1 inline h-4 w-4" />
            환불 완료 — 잔여 0, 상태가 '환불됨'으로 변경됐어요
          </p>
          <div className="rounded-[10px] bg-panel-2 p-3 text-[12.5px] leading-[1.9]">
            {/* v1.5: 환불액은 실수납(paid_sum)에서만 나간다 — 정산 근거를 결과에 함께 남긴다. */}
            실수납 {formatCurrency(refundPass.data.quote.paid_sum)} 기준 환불액 ={" "}
            <b className="text-brand">{formatCurrency(refundPass.data.quote.refund)}</b>
            <br />
            <span className="text-[11px] text-muted">
              {/* 원장에 실제로 찍히는 글자는 LEDGER_LABEL.refund = "환불"이다 — 화면에 없는
                  영어 단어("refund")를 찾으라고 하면 대표는 없는 줄을 뒤지게 된다. */}
              아래 세션 원장에 <b>환불</b> 기록이 남았습니다. 미납 회차는 청구 종결, 미서명 계약은
              무효 처리됐어요.
              {refundPass.data.quote.cancelled_bookings > 0 && (
                <>
                  {" "}
                  <b className="text-danger">
                    앞으로 잡혀 있던 예약 {refundPass.data.quote.cancelled_bookings}건이
                    취소됐어요
                  </b>{" "}
                  — 회원에게 알림이 가지 않으니 직접 안내해주세요.
                </>
              )}
            </span>
          </div>
          <Button className="w-full" onClick={onClose}>
            닫기
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal open onClose={onClose} title={`환불 계산기 — ${pass.product}`}>
      <div className="space-y-3">
        <div className="text-[11.5px] text-muted">
          {/* v1.5 어휘: paid_amount = 계약가(단가·위약금 산정 기준) — 환불액은 실수납 기준. */}
          계약가 {formatCurrency(pass.paid_amount)} · 총 {pass.total_sessions}회
        </div>
        <div className="rounded-[10px] bg-panel-2 px-3 py-2 text-[12.5px]">
          사용 <b>{used}회</b>{" "}
          <span className="text-[11px] text-muted">
            (원장 기준 — 총 {pass.total_sessions}회 − 잔여 {pass.remaining}회)
          </span>
        </div>
        <p className="text-[10.5px] text-muted">
          사용 횟수는 원장에서 자동 계산돼요 — 다른 횟수 시나리오 실험은 매출·통계의 환불
          계산기(정책 예시)를 사용하세요.
        </p>
        <Button
          className="w-full"
          disabled={refundQuote.isPending}
          onClick={() => refundQuote.mutate({ id: pass.id, used })}
        >
          <Calculator className="h-4 w-4" /> {refundQuote.isPending ? "계산 중…" : "계산하기"}
        </Button>
        {refundQuote.isError && <p className="text-[11px] text-danger">{refundQuote.error.message}</p>}
        {quoteStale && (
          <div className="rounded-[10px] border border-warn/40 bg-warn/[0.08] p-3">
            <p className="text-[11.5px] leading-relaxed text-warn">
              계산 이후 세션 원장이 바뀌었어요 — 사용 횟수가 {refundQuote.variables?.used}회에서{" "}
              {used}회가 됐습니다(다른 스태프가 수업을 완료·노쇼 처리했을 수 있어요). 아래 견적은
              옛 기준이라 그대로 실행할 수 없어요. "계산하기"를 다시 눌러주세요.
            </p>
          </div>
        )}
        {refundQuote.data && (
          <div
            className={`rounded-[10px] bg-panel-2 p-3 text-[12.5px] leading-[1.9] ${quoteStale ? "opacity-50" : ""}`}
          >
            회당 단가(계약가 기준) {formatCurrency(refundQuote.data.per_session)} × {used} ={" "}
            <b>{formatCurrency(refundQuote.data.usage)}</b> 공제
            <br />
            위약금 = <b>{formatCurrency(refundQuote.data.penalty)}</b>
            <br />
            <span className="text-[14px]">
              {/* v1.5: refund = max(실수납 − 이용 − 위약, 0) — 받은 돈에서만 나간다. */}
              실수납 {formatCurrency(refundQuote.data.paid_sum)} 기준 환불{" "}
              <b className="text-brand">{formatCurrency(refundQuote.data.refund)}</b>
            </span>
            {refundQuote.data.paid_sum < pass.paid_amount && (
              <p className="mt-1 text-[10.5px] text-warn">분할 미완납 — 실수납 기준 정산</p>
            )}
          </div>
        )}

        {refundQuote.data && isOwner && !confirming && !quoteStale && (
          <Button variant="danger" className="w-full" onClick={() => setConfirming(true)}>
            <Undo2 className="h-4 w-4" /> 환불 처리
          </Button>
        )}
        {confirming && !quoteStale && (
          <div className="rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
            <p className="text-[11.5px] leading-relaxed text-danger">
              이 회원권을 환불 처리합니다. 세션 원장에 <b>환불</b> 기록이 남고 되돌릴 수 없어요.
              {/*
                환불은 **앞으로 잡힌 수업도 함께 지운다**. 종전 문구는 그 사실을 말하지
                않았고(서버에 푸시가 없어 회원은 앱을 열어야 안다), 완료 화면도 부수효과
                셋 중 둘만 적었다 — 목록이 완결돼 보여서 누락이 더 위험했다.
                숫자는 견적이 실행과 **같은 판정**으로 세어 준 값이라 예고와 실제가 갈리지 않는다.
                0건이면 아무 말도 하지 않는다 — 없는 취소로 겁주지 않는다.
              */}
              {(refundQuote.data?.cancelled_bookings ?? 0) > 0 && (
                <>
                  {" "}
                  <b>
                    앞으로 잡힌 예약 {refundQuote.data!.cancelled_bookings}건도 함께
                    취소됩니다
                  </b>{" "}
                  — 회원에게 알림이 가지 않으니 직접 안내해주세요.
                </>
              )}
            </p>
            <div className="mt-2 flex gap-2">
              <Button
                size="sm"
                variant="danger"
                disabled={refundPass.isPending}
                onClick={() => refundPass.mutate({ id: pass.id, used })}
              >
                {refundPass.isPending ? "처리 중…" : "환불 처리 확정"}
              </Button>
              <Button size="sm" variant="ghost" disabled={refundPass.isPending} onClick={() => setConfirming(false)}>
                취소
              </Button>
            </div>
          </div>
        )}
        {refundPass.isError && <p className="text-[11px] text-danger">{refundPass.error.message}</p>}

        <p className="text-[10.5px] text-muted">
          {/* 내부 티켓·버전 표기(P5·v1.5)는 코드 주석에만 남긴다 — 화면에서는 대표가 확인할
              수 없는 기호다. P5 = 정가 공제 금지(법원·소비자원 공통 기준), v1.5 = 실수납 정산. */}
          회당 단가와 위약금은 <b>계약가</b>(정가가 아니라 할인 후 실제 거래가 — 법원·소비자원
          공통 기준)로 계산하고, 돌려드리는 돈은 <b>지금까지 실제로 받은 금액</b> 안에서만
          나갑니다.
        </p>
      </div>
    </Modal>
  );
}

function MemberFormModal({
  initial,
  staff,
  onClose,
}: {
  initial: Member | undefined;
  staff: Staff[];
  onClose: () => void;
}) {
  const [name, setName] = useState(initial?.name ?? "");
  const [phone, setPhone] = useState(initial?.phone ?? "");
  // 하이픈 유무 무관, 0으로 시작하는 9~11자리(휴대폰·지역번호 포괄) — P48 자동 매칭 키라 형식 가드.
  const phoneOk = /^0\d{8,10}$/.test(phone.replace(/[^0-9]/g, ""));
  const [channel, setChannel] = useState(initial?.channel ?? CHANNEL_OPTIONS[0]);
  const [trainerId, setTrainerId] = useState(initial?.trainer_id ?? "");
  const [hasInjury, setHasInjury] = useState(initial?.flags.some((f) => f.type === "injury") ?? false);
  const [injuryNote, setInjuryNote] = useState(
    initial?.flags.find((f) => f.type === "injury")?.note ?? "",
  );
  const [general, setGeneral] = useState(initial?.consent.general ?? false);
  const [sensitive, setSensitive] = useState(initial?.consent.sensitive ?? false);
  // 회원이 철회한 민감정보 동의(Consent.revoked_at). 이 폼에서 다시 켜지 못하게 한다 —
  // 아래 체크박스 자리 참고. 신규 등록에는 없는 상태(initial 없음)라 항상 null이다.
  const sensitiveRevokedAt = initial?.consent.revoked_at ?? null;

  // 신규 배정은 재직자만(v2.0) · 현재 값이 퇴사자면 그 항목만 별도로 붙여 값 유실을 막는다.
  const assignableStaff = staff.filter((s) => isStaffActive(s));
  const retiredCurrent = staff.find((s) => s.uid === trainerId && !isStaffActive(s)) ?? null;

  const createMember = useCreateMember();
  const updateMember = useUpdateMember();
  const pending = createMember.isPending || updateMember.isPending;
  const error = createMember.error ?? updateMember.error;

  function submit() {
    if (!name.trim() || !phone.trim()) return;
    const payload: Partial<Member> = {
      name: name.trim(),
      phone: phone.trim(),
      channel,
      trainer_id: trainerId,
      flags: hasInjury ? [{ type: "injury", note: injuryNote }] : [],
      consent: {
        general,
        sensitive,
        signed_at: initial?.consent.signed_at ?? (general || sensitive ? new Date().toISOString() : null),
        revoked_at: initial?.consent.revoked_at ?? null,
      },
    };
    if (initial) {
      updateMember.mutate({ id: initial.id, patch: payload }, { onSuccess: onClose });
    } else {
      createMember.mutate(
        { ...payload, app_linked: false, status: "active", last_visit_at: null },
        { onSuccess: onClose },
      );
    }
  }

  return (
    <Modal open onClose={onClose} title={initial ? "회원 정보 수정" : "회원 등록"}>
      <div className="space-y-3">
        <div>
          <Label>이름</Label>
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="홍길동" />
        </div>
        <div>
          <Label>전화번호</Label>
          <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="010-0000-0000" />
          {phone.trim() !== "" && !phoneOk && (
            // P48: 이 번호가 앱 자동 매칭의 키 — 오타로 남의 번호가 들어가는 것을 형식 수준에서 방지.
            <p className="mt-1 text-[10.5px] text-warn">전화번호 형식을 확인해주세요 (예: 010-1234-5678)</p>
          )}
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <Label>진입경로</Label>
            <Select value={channel} onChange={(e) => setChannel(e.target.value)}>
              {CHANNEL_OPTIONS.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label>담당 트레이너</Label>
            {/* 새로 고를 수 있는 건 재직자뿐이지만, 이미 퇴사자가 담당인 회원의 폼을 열었을 때
                셀렉트가 값을 잃으면 저장 한 번에 담당이 조용히 지워진다 — 현재 값은 disabled
                option으로 남겨 표시는 유지하고 재선택만 막는다. */}
            <Select value={trainerId} onChange={(e) => setTrainerId(e.target.value)}>
              <option value="">미배정</option>
              {retiredCurrent && (
                <option value={retiredCurrent.uid} disabled>
                  {staffLabel(retiredCurrent)}
                </option>
              )}
              {assignableStaff.map((s) => (
                <option key={s.uid} value={s.uid}>
                  {s.name}
                </option>
              ))}
            </Select>
            {retiredCurrent && (
              <p className="mt-1 text-[10.5px] text-warn">
                담당이 퇴사 처리됐어요 — 다른 트레이너를 고르거나 미배정으로 두세요.
              </p>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2 text-[12.5px]">
          <input type="checkbox" checked={hasInjury} onChange={(e) => setHasInjury(e.target.checked)} id="injury" />
          <label htmlFor="injury">부상 표시 (Home Work 자동 제외 대상)</label>
        </div>
        {hasInjury && (
          <Textarea
            value={injuryNote}
            onChange={(e) => setInjuryNote(e.target.value)}
            placeholder="예: 어깨 회전근개 — 오버헤드 동작 주의"
            rows={2}
          />
        )}

        <div className="flex flex-col gap-1.5 text-[12.5px]">
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={general} onChange={(e) => setGeneral(e.target.checked)} />
            일반 개인정보 처리 동의
          </label>
          {/* **철회된 동의는 이 폼에서 다시 켤 수 없다.** 종전엔 체크박스가 이미 켜진 채로
              열리고, 저장해도 철회 기록(revoked_at)은 그대로 보존돼(아래 submit) 화면만
              "동의됨"으로 보이고 체형 분석은 계속 잠긴 상태였다 — 대표는 뭔가 했다고 믿는데
              아무것도 바뀌지 않는 자리였다. 민감정보 동의는 회원 본인만 줄 수 있으므로
              여기서 대신 켜 주는 것 자체가 잘못된 동선이다. 체크박스 대신 사실을 적는다. */}
          {sensitiveRevokedAt ? (
            <div className="rounded-[10px] border border-danger/35 bg-danger/[0.08] px-2.5 py-2">
              <div className="font-bold text-danger">
                민감정보(체형사진 등) 처리 동의 — 회원이 철회함 ({sensitiveRevokedAt.slice(0, 10)})
              </div>
              <p className="mt-0.5 text-[10.5px] leading-relaxed text-danger">
                체형사진 촬영·열람이 잠겨 있어요. <b>회원이 앱 마이 탭의 "민감정보(인바디·체형사진)
                동의"에서 다시 동의하면 바로 열려요 — 여기서는 켤 수 없어요.</b> 이미 찍어 둔 사진은
                지워지지 않아요.
              </p>
            </div>
          ) : (
            <label className="flex items-center gap-2">
              <input type="checkbox" checked={sensitive} onChange={(e) => setSensitive(e.target.checked)} />
              민감정보(체형사진 등) 처리 동의
            </label>
          )}
        </div>

        {error && <p className="text-[11px] text-danger">{error.message}</p>}

        <Button className="w-full" disabled={!name.trim() || !phoneOk || pending} onClick={submit}>
          <UserPlus className="h-4 w-4" /> {initial ? "저장" : "등록"}
        </Button>
        <p className="text-[10.5px] text-muted">
          {/* 내부 티켓 표기(P48 = 번호 기반 자동 매칭)는 코드 주석에만 남긴다. */}
          등록 후 회원이 앱에서 같은 번호로 인증하면 자동으로 연결됩니다 — 이름 확인 1탭이면 끝이에요.
        </p>
      </div>
    </Modal>
  );
}

// 추가결제 원스톱 플로우(v1.1 정합 패치 확정): 회원권 발급(POST /v1/passes) → 결제 기록
// (POST /v1/payments) → 쿼리 무효화. 서명 대기(sent) 계약 자동 생성은 백엔드가 회원권 발급
// 시점에 처리한다고 가정(계약: "발급 시 자동 생성 가능") — 결제 성공 시 계약 목록도 함께
// 무효화해 반영한다(useCreatePayment 참고).
// v1.5: 결제 기록 없는 active 패스(대시보드 "결제 기록 없는 회원권" 경고 대상)가 있으면
// "그 패스에 결제만 기록" 모드를 제공 — 발급을 스킵해 유령 이중 발급을 막는다.
function AddContractModal({
  member,
  staff,
  onClose,
}: {
  member: MemberWithPasses;
  staff: Staff[];
  onClose: () => void;
}) {
  const { me } = useAuth();
  const isOwner = me?.role === "owner";
  const [product, setProduct] = useState("");
  // 트레이너 발급은 본인 담당만 서버가 허용(타 담당은 403) — 트레이너는 본인으로 초기화한다.
  // 회원의 현재 담당이 퇴사자면 프리필하지 않는다(v2.0): 퇴사자 명의로 새 회원권을 끊으면
  // 그 패스로는 예약을 만들 수 없고(서버 400), 그 사람의 퇴사 선행 조건만 되살아난다.
  const [trainerId, setTrainerId] = useState(
    isOwner
      ? (staff.find((s) => s.uid === member.trainer_id && isStaffActive(s))?.uid ?? "")
      : (me?.uid ?? ""),
  );
  const [totalSessions, setTotalSessions] = useState(20);
  const [paidAmount, setPaidAmount] = useState(1_000_000);
  const [validUntil, setValidUntil] = useState(addDays(todayStr(), 180));
  const [method, setMethod] = useState<Payment["method"]>("card");
  const [split, setSplit] = useState(false);
  const [due1, setDue1] = useState(todayStr());
  const [due2, setDue2] = useState(addDays(todayStr(), 30));
  // 분할 1차는 기본이 "지금 받았다"(즉시 완납)다. 종전엔 이게 강제라 1차 납부일에 다음 주를
  // 넣어도 오늘 완납으로 기록돼 미수금에서 빠졌다 — 아직 안 받았으면 미수로 남길 수 있게 한다.
  const [firstUnpaid, setFirstUnpaid] = useState(false);
  // 발급된 회원권 id 보관 — createPass 성공 후 createPayment가 실패했을 때 재제출하면
  // 발급을 건너뛰고 결제만 재시도해 Pass 이중 발급을 막는다.
  const [createdPassId, setCreatedPassId] = useState<string | null>(null);
  // v1.5: "결제만 기록" 모드 대상 패스(null = 새 회원권 발급 모드).
  const [payOnlyPassId, setPayOnlyPassId] = useState<string | null>(null);
  // pay-only 전환 시 계약가 프리필이 발급 폼에 입력해둔 금액을 덮는다 — 복귀 대비 보관.
  const [issueAmountBackup, setIssueAmountBackup] = useState<number | null>(null);

  // 트레이너 역할이면 발급 대상 트레이너 옵션을 본인만으로 한정 — 서버 403을 UI에서 사전 차단.
  // v2.0: 어느 역할이든 퇴사자는 뺀다(신규 배정은 재직자만).
  const staffOptions = (isOwner ? staff : staff.filter((s) => s.uid === me?.uid)).filter((s) =>
    isStaffActive(s),
  );

  // MemberDetail의 결제 목록과 같은 캐시 키 — 추가 요청 없이 재사용된다.
  const paymentsQ = usePayments(member.id);
  const unrecordedPasses = (member.passes ?? []).filter(
    (p) =>
      // scheduled(아직 시작 전 재등록)도 포함한다 — 돈은 이미 받았는데 결제 기록만
      // 없는 상태라, 여기서 빼면 미기록 매출이 조용히 사라진다(P25로 상태가 실제로
      // 내려오기 시작하면서 생긴 자리).
      isPassBookable(p) &&
      // 트레이너의 결제 조회 응답은 담당 패스 분만 온다 — 타 담당 패스는 결제가 있어도 0건으로
      // 보여 "무결제" 오탐 → 결제만 기록 시도 시 403 막다른길. 트레이너는 본인 담당 패스만 검사.
      (isOwner || p.trainer_id === me?.uid) &&
      paymentsQ.data !== undefined && // 로딩 중엔 오탐(전부 0건) 방지 — 선택지 미노출
      !paymentsQ.data.some((pay) => pay.pass_id === p.id),
  );
  const payOnlyPass = unrecordedPasses.find((p) => p.id === payOnlyPassId) ?? null;

  const createPass = useCreatePass();
  const createPayment = useCreatePayment();
  const pending = createPass.isPending || createPayment.isPending;
  const error = createPass.error ?? createPayment.error;

  const canSubmit = payOnlyPass
    ? paidAmount > 0 && (!split || (!!due1 && !!due2))
    : !!product.trim() &&
      !!trainerId &&
      totalSessions > 0 &&
      paidAmount > 0 &&
      !!validUntil &&
      (!split || (!!due1 && !!due2));

  // **잠긴 버튼은 이유를 말한다.** 종전엔 "계약 등록"이 회색으로 죽어 있기만 해서 어느 칸이
  // 비었는지 알 수 없었고, 특히 재직 트레이너가 하나도 없으면(전원 퇴사 처리) 담당 셀렉트에
  // 고를 값이 없어 **이 폼 안에서는 영원히 풀리지 않는 잠금**이 된다 — 그 경우의 다음 행동은
  // 이 화면 밖(설정 · 직원)에 있으므로 그것부터 말한다.
  // canSubmit이 거짓인 동안만 띄운다 — 눌리는 버튼 옆에 "왜 안 눌리는지"가 붙는 모순 방지.
  const disabledReason = !canSubmit
    ? payOnlyPass
      ? paidAmount <= 0
        ? "결제 금액을 입력해주세요."
        : "분할 납부 날짜(1차·2차)를 모두 골라주세요."
      : staffOptions.length === 0
        ? "지금 회원권을 맡길 수 있는 트레이너가 없어요 — 설정 · 직원에서 트레이너를 초대한 뒤 다시 시도해주세요."
        : !product.trim()
          ? "상품명을 입력해주세요."
          : !trainerId
            ? "담당 트레이너를 골라주세요."
            : totalSessions <= 0
              ? "총 세션 수를 1회 이상으로 입력해주세요."
              : paidAmount <= 0
                ? "계약가를 입력해주세요."
                : !validUntil
                  ? "이용 만료일을 골라주세요."
                  : "분할 납부 날짜(1차·2차)를 모두 골라주세요."
    : null;

  function submitPayment(passId: string) {
    // 실결제 전액을 등록 시점에 즉시 수납한다고 가정(비분할). 분할 시 1차는 즉시 완납,
    // 2차는 미납 상태로 기록해 회원 상세 "결제 목록"의 미납 하이라이트·납부 처리로 이어진다.
    // paid_at은 백엔드 도메인 타입이 *time.Time — RFC3339 필수(YYYY-MM-DD는 400).
    // due는 계약 확정된 날짜 문자열(YYYY-MM-DD) 유지.
    const paidNow = new Date().toISOString();
    const firstAmount = split ? Math.ceil(paidAmount / 2) : paidAmount;
    const installments: Payment["installments"] = split
      ? [
          // 1차는 기본 즉시 완납, "1차도 아직 미수" 체크 시 미납으로 남긴다(due1이 납부기한).
          { due: due1, amount: firstAmount, paid_at: firstUnpaid ? null : paidNow },
          { due: due2, amount: paidAmount - firstAmount, paid_at: null },
        ]
      : [{ due: todayStr(), amount: paidAmount, paid_at: paidNow }];

    createPayment.mutate(
      {
        member_id: member.id,
        pass_id: passId,
        method,
        total: paidAmount,
        installments,
        // CHANNEL_OPTIONS의 "재등록"과 동일 개념 — 계약 등록 시점의 진입경로(설계 03 §R7).
        channel: "재등록",
      },
      {
        onSuccess: () => {
          setCreatedPassId(null);
          onClose();
        },
      },
    );
  }

  function submit() {
    if (!canSubmit) return;
    // v1.5 "결제만 기록" 모드 — 기존 패스에 결제만 남긴다(발급·계약 생성 스킵).
    if (payOnlyPass) {
      submitPayment(payOnlyPass.id);
      return;
    }
    // 직전 제출에서 회원권 발급까지 성공하고 결제만 실패한 경우 — 결제만 재시도.
    if (createdPassId) {
      submitPayment(createdPassId);
      return;
    }
    createPass.mutate(
      {
        member_id: member.id,
        trainer_id: trainerId,
        product: product.trim(),
        paid_amount: paidAmount,
        total_sessions: totalSessions,
        valid_from: todayStr(),
        valid_until: validUntil,
      },
      {
        onSuccess: (pass) => {
          setCreatedPassId(pass.id);
          submitPayment(pass.id);
        },
      },
    );
  }

  return (
    <Modal open onClose={onClose} title={`추가 계약(재등록) — ${member.name}`}>
      <div className="space-y-3">
        {/* v1.5: 발급만 되고 결제 기록이 없는 active 패스가 있으면 "결제만 기록" 선택지 제공
            — 새로 발급하면 같은 회원권이 이중으로 생긴다(대시보드 경고 항목의 해소 경로). */}
        {unrecordedPasses.length > 0 && (
          <div className="rounded-[10px] border border-warn/40 bg-warn/[0.08] p-3">
            <p className="text-[11.5px] leading-relaxed text-warn">
              결제 기록이 없는 회원권이 있어요 — 이 회원권에 결제만 기록할 수 있어요.
            </p>
            <div className="mt-1.5">
              <Chip
                active={!payOnlyPass}
                onClick={() => {
                  setPayOnlyPassId(null);
                  // 발급 모드 복귀 — 전환 전 입력해둔 발급 금액을 복원한다.
                  if (issueAmountBackup !== null) {
                    setPaidAmount(issueAmountBackup);
                    setIssueAmountBackup(null);
                  }
                }}
              >
                새 회원권 발급 + 결제
              </Chip>
              {unrecordedPasses.map((p) => (
                <Chip
                  key={p.id}
                  active={payOnlyPassId === p.id}
                  onClick={() => {
                    // 발급 모드에서 넘어올 때만 보관 — 패스 간 전환이 백업을 덮지 않게.
                    if (payOnlyPassId === null) setIssueAmountBackup(paidAmount);
                    setPayOnlyPassId(p.id);
                    setPaidAmount(p.paid_amount); // 계약가로 프리필(수정 가능 — 부분 수납 기록)
                  }}
                >
                  {p.product} — 결제만 기록
                </Chip>
              ))}
            </div>
          </div>
        )}

        {payOnlyPass ? (
          <div className="rounded-[10px] bg-panel-2 px-3 py-2 text-[11.5px] text-muted">
            대상 회원권: <b className="text-ink">{payOnlyPass.product}</b> · 총{" "}
            {payOnlyPass.total_sessions}회 · ~{payOnlyPass.valid_until} · 계약가{" "}
            {formatCurrency(payOnlyPass.paid_amount)} — 발급은 건너뛰고 결제만 기록합니다.
          </div>
        ) : (
          <>
            <div>
              <Label>상품명</Label>
              <Input value={product} onChange={(e) => setProduct(e.target.value)} placeholder="예: PT 20회 패키지" />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <Label>담당 트레이너</Label>
                <Select value={trainerId} onChange={(e) => setTrainerId(e.target.value)}>
                  <option value="">선택</option>
                  {staffOptions.map((s) => (
                    <option key={s.uid} value={s.uid}>
                      {s.name}
                    </option>
                  ))}
                </Select>
              </div>
              <div>
                <Label>총 세션 수</Label>
                <Input
                  type="number"
                  min={1}
                  value={totalSessions}
                  onChange={(e) => setTotalSessions(Number(e.target.value))}
                />
              </div>
            </div>
          </>
        )}
        <div className="grid grid-cols-2 gap-2">
          <div>
            {/*
              같은 칸이 모드에 따라 다른 값을 뜻한다 — 라벨이 하나면 반드시 한쪽이 거짓이 된다.
              · 발급: 이 값이 `Pass.paid_amount` = **계약가**가 된다. 회차 단가(계약가÷총회차)와
                위약금(계약가×요율)이 전부 여기서 나온다(고시 제2019-9호 별표 "총계약대금의 10%").
                분할이라고 1차분을 적으면 단가·위약금·환불이 통째로 어긋난다.
              · 결제만 기록: 이 회차에 **실제로 받은 돈**이다(실수납 = 결제 회차 합).
            */}
            <Label>{payOnlyPass ? "결제 금액(실수납)" : "계약가"}</Label>
            <Input type="number" min={0} value={paidAmount} onChange={(e) => setPaidAmount(Number(e.target.value))} />
            {!payOnlyPass && (
              <p className="mt-1 text-[10.5px] text-muted">
                분할로 받아도 <b>계약서에 적힌 총액</b>을 넣어주세요 — 회차 단가와 위약금이 이
                값으로 계산돼요. 실제 받은 돈은 아래 결제 회차로 기록됩니다.
              </p>
            )}
          </div>
          {!payOnlyPass && (
            <div>
              <Label>이용 만료일</Label>
              <Input type="date" value={validUntil} onChange={(e) => setValidUntil(e.target.value)} />
            </div>
          )}
        </div>
        {/* v1.5 어휘: pay-only에서 계약가와 다른 금액은 막지 않는다(부분 수납 허용) — 의도 확인 힌트만. */}
        {payOnlyPass && paidAmount > 0 && paidAmount !== payOnlyPass.paid_amount && (
          <p className="text-[10.5px] text-muted">
            계약가와 다른 금액이에요 — 부분 수납 기록으로 남아요.
          </p>
        )}

        <div>
          <Label>결제 방법</Label>
          <div>
            <Chip active={method === "card"} onClick={() => setMethod("card")}>
              카드
            </Chip>
            <Chip active={method === "cash"} onClick={() => setMethod("cash")}>
              현금
            </Chip>
            <Chip active={method === "transfer"} onClick={() => setMethod("transfer")}>
              계좌이체
            </Chip>
          </div>
        </div>

        <div className="flex items-center gap-2 text-[12.5px]">
          <input type="checkbox" checked={split} onChange={(e) => setSplit(e.target.checked)} id="split" />
          <label htmlFor="split">2회 분할 결제</label>
        </div>
        {split && (
          <>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <Label>{firstUnpaid ? "1차 납부기한" : "1차 수납일 (즉시 완납으로 기록)"}</Label>
                <Input type="date" value={due1} onChange={(e) => setDue1(e.target.value)} />
              </div>
              <div>
                <Label>2차 납부기한</Label>
                <Input type="date" value={due2} onChange={(e) => setDue2(e.target.value)} />
              </div>
            </div>
            <label className="flex items-center gap-2 text-[12.5px]">
              <input
                type="checkbox"
                checked={firstUnpaid}
                onChange={(e) => setFirstUnpaid(e.target.checked)}
              />
              1차도 아직 받지 않았어요 (미수로 기록)
            </label>
            <p className="text-[10.5px] leading-relaxed text-muted">
              {firstUnpaid
                ? "1·2차 모두 미납으로 기록돼 미수금에 잡혀요 — 받으면 \"결제 목록\"에서 납부 처리하세요."
                : "1차는 오늘 받은 것으로 즉시 완납 기록돼요(날짜를 미래로 넣어도 완납 시각은 오늘입니다). 아직 안 받았다면 위 체크박스를 켜세요."}
            </p>
            {due2 && due1 && due2 < due1 && (
              <p className="text-[11px] text-warn">2차 날짜는 1차 이후여야 해요.</p>
            )}
          </>
        )}

        {error && <p className="text-[11px] text-danger">{error.message}</p>}
        {!payOnlyPass && createdPassId && createPayment.isError && (
          <p className="text-[10.5px] text-muted">
            회원권은 이미 발급되었습니다 — 다시 제출하면 결제 기록만 재시도합니다.
          </p>
        )}

        {disabledReason && !pending && (
          <p className="text-[10.5px] leading-relaxed text-warn">{disabledReason}</p>
        )}
        <Button className="w-full" disabled={!canSubmit || pending} onClick={submit}>
          <FileSignature className="h-4 w-4" />{" "}
          {pending ? "등록 중…" : payOnlyPass ? "결제만 기록" : "계약 등록"}
        </Button>
        <p className="text-[10.5px] text-muted">
          {/* 내부 버전 표기(v1.1 추가결제 플로우)와 상태 코드(sent)는 코드 주석에만 남긴다 —
              화면에는 대표가 실제로 보게 될 말("서명 대기")로 쓴다. */}
          {payOnlyPass
            ? "기존 회원권에 결제 기록만 추가합니다 — 발급·계약서 발송은 일어나지 않아요. 분할 결제의 2차 납부는 \"결제 목록\"에서 납부 처리로 완결하세요."
            : "회원권 발급 → 계약서 발송(서명 대기) → 결제 기록까지 한 번에 처리합니다. 분할 결제의 2차 납부는 등록 후 \"결제 목록\"에서 납부 처리로 완결하세요."}
        </p>
      </div>
    </Modal>
  );
}
