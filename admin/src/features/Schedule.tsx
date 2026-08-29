// 예약 — 목업 s-cal 1:1. 시간당 레인(기본 3) + 트레이너 색상 태깅 + 예약 생성/완료/노쇼/취소.
// 트레이너는 "패스 선택 → 코치가 따라온다"(설계03 R4) — 모달엔 트레이너 선택이 없고 패스가 결정한다.
// v1.4: 완료 처리 직후 같은 모달에서 "수업 기록(30초, P29)" 선택 입력 + 고정 스케줄 관리 패널(P47).
import { useMemo, useState } from "react";
import { Ban, Check, ChevronDown, ChevronRight, Dumbbell, Plus, Repeat, Trash2, XCircle } from "lucide-react";
import {
  Badge,
  Button,
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
} from "@/components/ui";
import { useAuth } from "@/lib/auth";
import {
  useBookings,
  useCancelBooking,
  useCenter,
  useCompleteBooking,
  useCreateBooking,
  useCreateRecurring,
  useCreateWorkoutLog,
  useDeleteRecurring,
  useMembers,
  useNoshowBooking,
  useRecurrings,
  useSlots,
  useStaff,
} from "@/lib/queries";
import {
  addDays,
  buildSlotKey,
  dateToWeekday,
  formatDow,
  isStaffActive,
  slotKeyStart,
  slotKeyToDate,
  slotKeyToHour,
  staffLabel,
  todayStr,
} from "@/lib/format";
import {
  WEEKDAY_LABEL,
  isPassBookable,
  type BookingKind,
  type Exercise,
  type Slot,
  type SlotTeam,
  type Weekday,
} from "@/lib/types";

const KIND_LABEL: Record<BookingKind, string> = { pt: "1:1", group: "그룹", ot: "체험(OT)" };
const DEFAULT_HOURS = Array.from({ length: 13 }, (_, i) => i + 9); // 09~21시(센터 운영시간 API 없어 기본값)

// 이름 자리의 폴백 — **raw 문서ID/uid는 어떤 경우에도 노출하지 않는다**. mem_7Kd2…·t1 같은
// 값은 사람이 읽을 정보가 아니고(개인정보 최소 노출 원칙에도 어긋난다), "이름을 못 풀었다"와
// "그런 이름이다"를 구분할 수 없게 만든다. 미해석은 미해석이라고 쓴다.
const UNRESOLVED_MEMBER_SLOT = "예약됨"; // 그리드 블록·예약 상세(누구인지 안 밝히는 자리)
const UNRESOLVED_MEMBER_ROW = "(이름 미확인)"; // 표 행(무엇이 비었는지 알려야 하는 자리)
const UNRESOLVED_STAFF = "(담당 미확인)";

type ModalState =
  | { mode: "create"; slotKey: string }
  | { mode: "manage"; slotKey: string; team: SlotTeam };

export function Schedule() {
  const [date, setDate] = useState(todayStr());
  const [modal, setModal] = useState<ModalState | null>(null);

  const slotsQ = useSlots(date);
  const staffQ = useStaff();
  // 그리드는 회원 목록을 HourRow에서 같은 캐시로 읽는다 — 조회 실패를 여기서 한 번만 알린다
  // (실패하면 모든 블록이 "예약됨"으로 마스킹돼, 배너가 없으면 "타 담당 수업"과 구분되지 않는다).
  const membersQ = useMembers();
  // v1.5: 예약 없는 날의 레인 수 폴백 — 하드코딩 3 대신 센터 정책(slot_capacity) 실값.
  const centerQ = useCenter();

  // 그리드·범례가 함께 쓰는 uid → 표시 정보. v2.0: 퇴사자도 담는다 — 퇴사한 코치의 지난·예정
  // 블록이 그대로 남아 있어서, 여기서 빼면 이름 자리에 원시 uid가 찍히고 색은 폴백 빨강 하나로
  // 뭉개진다(누구 수업인지 구분 불가).
  const staffByUid = useMemo(() => {
    const map = new Map<string, { name: string; color: string }>();
    for (const s of staffQ.data ?? []) map.set(s.uid, { name: staffLabel(s), color: s.color || "#f43f5e" });
    return map;
  }, [staffQ.data]);

  // 색상 범례 — 재직자를 앞에, 퇴사자를 뒤에. 범례에서 퇴사자를 빼면 그리드에 남은 그 색의
  // 블록을 해석할 수 없다(색만 있고 주인이 없는 상태). 대신 흐리게 + "(퇴사)"로 구분한다.
  const legend = useMemo(() => {
    const list = staffQ.data ?? [];
    return [...list.filter((s) => isStaffActive(s)), ...list.filter((s) => !isStaffActive(s))];
  }, [staffQ.data]);

  const slotByHour = useMemo(() => {
    const map = new Map<number, Slot>();
    for (const s of slotsQ.data ?? []) map.set(slotKeyToHour(s.slot_key), s);
    return map;
  }, [slotsQ.data]);

  // 서버 용량 그대로 신뢰(3 미만이어도 하한 3으로 부풀리지 않는다 — 가짜 레인 클릭 → 서버 거부 방지).
  // 슬롯이 하나도 없는 날은 센터 정책의 slot_capacity로 폴백(정책 로딩 전엔 시드 기본값 3).
  const capacity = useMemo(() => {
    const caps = (slotsQ.data ?? []).map((s) => s.capacity);
    return caps.length ? Math.max(...caps) : (centerQ.data?.policy.slot_capacity ?? 3);
  }, [slotsQ.data, centerQ.data]);

  // 그리드 열 수 — capacity를 초과해 저장된 팀(정책 변경 이력 등)도 화면에서 소실되지 않게.
  const laneCols = useMemo(() => {
    const teamCounts = (slotsQ.data ?? []).map((s) => s.teams.length);
    return Math.max(capacity, ...teamCounts);
  }, [slotsQ.data, capacity]);

  const hours = useMemo(() => {
    const set = new Set<number>(DEFAULT_HOURS);
    for (const h of slotByHour.keys()) set.add(h);
    return Array.from(set).sort((a, b) => a - b);
  }, [slotByHour]);

  const nearbyDates = useMemo(() => {
    const out: string[] = [];
    for (let i = -2; i <= 2; i++) out.push(addDays(date, i));
    return out;
  }, [date]);

  return (
    <div>
      <h2 className="text-[16.5px] font-bold">예약 — 시간당 최대 {capacity}팀</h2>
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        한 시간에 {capacity}레인(동시 {capacity}세션). 초과 예약은 저장 시 자동 차단, 트레이너는
        같은 시간 1팀만.
      </p>

      <div className="rounded-[13px] border border-line bg-panel p-3.5">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap items-center">
            {nearbyDates.map((d) => (
              <Chip key={d} active={d === date} onClick={() => setDate(d)}>
                {formatDow(d)} {Number(d.split("-")[2])}
              </Chip>
            ))}
            <input
              type="date"
              value={date}
              // 클리어(빈 문자열)로 slots?date= 빈 조회가 되지 않게 오늘로 폴백.
              onChange={(e) => setDate(e.target.value || todayStr())}
              className="ml-1.5 rounded-[10px] border border-line bg-panel-2 px-2 py-1 text-[11px] text-ink"
            />
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            {legend.map((s) => {
              const color = s.color || "#f43f5e";
              return (
                <Badge
                  key={s.uid}
                  className={isStaffActive(s) ? "border" : "border opacity-60"}
                  style={{ background: `${color}29`, color }}
                >
                  {staffLabel(s)}
                </Badge>
              );
            })}
            <Button
              size="sm"
              onClick={() => setModal({ mode: "create", slotKey: buildSlotKey(date, hours[0] ?? 10) })}
            >
              <Plus className="h-3.5 w-3.5" /> 예약 (대행)
            </Button>
          </div>
        </div>

        {/* 조회 실패는 그리드를 지우지 않는다(예약 자체는 보여야 한다) — 대신 "지금 화면에서
            무엇을 믿으면 안 되는지"를 한 줄로 못박는다. 종전엔 둘 다 조용히 실패해서 회원명은
            전부 마스킹, 담당·색은 폴백 한 색으로 뭉개진 화면이 정상처럼 보였다. */}
        {membersQ.isError && (
          <p className="mb-2 rounded-[10px] border border-danger/40 bg-danger/[0.08] px-3 py-2 text-[11px] text-danger">
            회원 목록을 불러오지 못했어요 — 모든 블록의 회원명이 "예약됨"으로 표시됩니다.
            ({membersQ.error.message})
          </p>
        )}
        {staffQ.isError && (
          <p className="mb-2 rounded-[10px] border border-warn/40 bg-warn/[0.08] px-3 py-2 text-[11px] text-warn">
            직원 목록을 불러오지 못했어요 — 색상 범례가 비고 모든 블록이 같은 색·"{UNRESOLVED_STAFF}"로
            표시됩니다. ({staffQ.error.message})
          </p>
        )}
        {slotsQ.isLoading ? (
          <Spinner />
        ) : slotsQ.isError ? (
          <ErrorState error={slotsQ.error} />
        ) : (
          <div
            className="grid gap-1.5 text-[11px]"
            style={{ gridTemplateColumns: `44px repeat(${laneCols}, 1fr)` }}
          >
            <div />
            {Array.from({ length: laneCols }, (_, i) => (
              <div key={i} className="pb-0.5 text-center text-[10.5px] text-muted">
                레인 {i + 1}
              </div>
            ))}
            {hours.map((h) => {
              const slot = slotByHour.get(h);
              const teams = slot?.teams ?? [];
              const slotKey = buildSlotKey(date, h);
              return (
                <HourRow
                  key={h}
                  hour={h}
                  capacity={capacity}
                  laneCols={laneCols}
                  teams={teams}
                  slotKey={slotKey}
                  staffByUid={staffByUid}
                  onEmptyClick={() => setModal({ mode: "create", slotKey })}
                  onTeamClick={(team) => setModal({ mode: "manage", slotKey, team })}
                />
              );
            })}
          </div>
        )}

        {/* waitlist(대기 신청·자동 승격)는 v1 제외 — 근거 없는 기능 안내를 지웠다(v1.5). */}
        <p className="mt-2.5 text-[10.5px] leading-relaxed text-muted">
          빈 레인 클릭 = 대행 예약(회원/회원권 선택). 용량은 설정 화면에서 변경할 수 있습니다.
        </p>
      </div>

      <RecurringPanel hours={hours} />

      {modal?.mode === "create" && (
        <CreateBookingModal slotKey={modal.slotKey} hours={hours} date={date} onClose={() => setModal(null)} />
      )}
      {modal?.mode === "manage" && (
        <ManageBookingModal
          team={modal.team}
          slotKey={modal.slotKey}
          trainerName={staffByUid.get(modal.team.trainer_id)?.name ?? UNRESOLVED_STAFF}
          onClose={() => setModal(null)}
        />
      )}
    </div>
  );
}

function HourRow({
  hour,
  capacity,
  laneCols,
  teams,
  slotKey,
  staffByUid,
  onEmptyClick,
  onTeamClick,
}: {
  hour: number;
  capacity: number;
  laneCols: number;
  teams: SlotTeam[];
  slotKey: string;
  staffByUid: Map<string, { name: string; color: string }>;
  onEmptyClick: () => void;
  onTeamClick: (team: SlotTeam) => void;
}) {
  const membersQ = useMembers();
  // 목업 s-cal 규칙: 트레이너 뷰에서 타 코치 팀은 회원명 대신 "예약됨"으로 마스킹(개인정보 최소 노출).
  // 회원 목록이 담당 스코프라 이름 해석이 안 되는 경우이기도 하고, 목록 조회 자체가 실패했을
  // 수도 있다 — 세 경우 모두 "예약됨"으로 통일한다(raw member_id는 절대 노출하지 않는다).
  // 조회 실패는 이름 자리가 아니라 그리드 상단 배너가 알린다(Schedule 본체).
  const displayName = (team: SlotTeam) => {
    const found = membersQ.data?.find((m) => m.id === team.member_id)?.name;
    if (found) return found;
    if (membersQ.isLoading) return "…";
    return UNRESOLVED_MEMBER_SLOT;
  };
  // 행별 레인 수 — capacity 초과로 저장된 팀도 소실 없이 그린다. lanes를 넘는 열은
  // 그리드 정렬용 빈 자리(클릭 불가)로 채운다.
  const lanes = Math.max(capacity, teams.length);
  return (
    <>
      <div className="pt-2 text-right text-[10.5px] text-muted">{hour}시</div>
      {Array.from({ length: laneCols }, (_, i) => {
        const team = teams[i];
        if (team) {
          return (
            <button
              key={team.booking_id}
              onClick={() => onTeamClick(team)}
              className="min-h-[34px] rounded-lg border-l-[3px] p-1.5 text-left font-bold leading-snug transition hover:brightness-110"
              style={{
                background: `${staffByUid.get(team.trainer_id)?.color ?? "#f43f5e"}26`,
                borderLeftColor: staffByUid.get(team.trainer_id)?.color ?? "#f43f5e",
                color: staffByUid.get(team.trainer_id)?.color ?? "#f43f5e",
              }}
            >
              {displayName(team)} {KIND_LABEL[team.kind]}
              {team.status === "completed" && <Check className="ml-1 inline h-3 w-3" />}
              {team.status === "noshow" && <span className="block font-normal opacity-70">노쇼</span>}
              <span className="block font-normal text-muted">
                {staffByUid.get(team.trainer_id)?.name ?? UNRESOLVED_STAFF}
              </span>
            </button>
          );
        }
        if (i < lanes) {
          return (
            <button
              key={`${slotKey}-empty-${i}`}
              onClick={onEmptyClick}
              aria-label={`${hour}시 레인 ${i + 1} 예약 추가`}
              className="flex min-h-[34px] items-center justify-center rounded-lg border border-dashed border-line text-muted transition hover:border-brand hover:text-brand"
            >
              <Plus className="h-3.5 w-3.5" />
            </button>
          );
        }
        return <div key={`${slotKey}-pad-${i}`} aria-hidden className="min-h-[34px]" />;
      })}
    </>
  );
}

function CreateBookingModal({
  slotKey: initialSlotKey,
  hours,
  date,
  onClose,
}: {
  slotKey: string;
  hours: number[];
  date: string;
  onClose: () => void;
}) {
  const [hour, setHour] = useState(slotKeyToHour(initialSlotKey));
  const [memberId, setMemberId] = useState("");
  const [passId, setPassId] = useState("");
  // v1.4(P47): 체크 시 단건 예약 대신 고정 스케줄 등록 — 요일은 선택 날짜의 요일, 종료일은 +8주 기본.
  const [repeatWeekly, setRepeatWeekly] = useState(false);
  const membersQ = useMembers();
  const staffQ = useStaff();
  const createBooking = useCreateBooking();
  const createRecurring = useCreateRecurring();

  // 기존 데이터 표시 — 퇴사자도 계속 해석하되 "(퇴사)"를 붙인다(계약 v2.0).
  const staffName = (uid: string) => {
    const s = staffQ.data?.find((x) => x.uid === uid);
    return s ? staffLabel(s) : UNRESOLVED_STAFF;
  };
  const selectedMember = membersQ.data?.find((m) => m.id === memberId);
  // 서버 BookableStatus와 같은 판정 — scheduled(시작 전 재등록)도 선예약 대상이다.
  const availablePasses = (selectedMember?.passes ?? []).filter(
    (p) => isPassBookable(p) && p.remaining > 0,
  );
  const selectedPass = availablePasses.find((p) => p.id === passId);
  // 담당이 퇴사 처리된 패스로는 새 예약도 고정 스케줄도 만들 수 없다(서버 400 — 휴무일 거부와
  // 같은 자리). 패스가 담당을 결정하는 구조라 이 창엔 트레이너 셀렉트가 없으니, 눌러보고 400을
  // 받는 대신 이유와 해법을 먼저 보여준다.
  const passTrainerRetired =
    !!selectedPass && !isStaffActive(staffQ.data?.find((s) => s.uid === selectedPass.trainer_id));
  const pending = createBooking.isPending || createRecurring.isPending;
  const error = createBooking.error ?? createRecurring.error;

  function submit() {
    if (!memberId || !passId) return;
    if (repeatWeekly) {
      if (!selectedPass) return;
      createRecurring.mutate({
        member_id: memberId,
        trainer_id: selectedPass.trainer_id, // 패스가 담당을 결정(설계03 R4)
        pass_id: passId,
        days: [dateToWeekday(date)],
        hour,
        until: addDays(date, 56), // +8주 기본
      });
      // 성공 시 모달을 바로 닫지 않고 "4주치 선행 예약" 안내를 보여준다(아래 isSuccess 분기).
      return;
    }
    createBooking.mutate(
      { slot_key: buildSlotKey(date, hour), member_id: memberId, pass_id: passId },
      { onSuccess: onClose },
    );
  }

  if (createRecurring.isSuccess) {
    return (
      <Modal open onClose={onClose} title="예약 생성 (대행)">
        <div className="space-y-3">
          <p className="text-[12.5px] text-ok">
            <Check className="mr-1 inline h-3.5 w-3.5" />
            고정 스케줄로 등록됐어요 — 앞으로 4주 안의 회차가 자동 예약됐어요.
          </p>
          <p className="text-[10.5px] text-muted">
            매주 {WEEKDAY_LABEL[dateToWeekday(date)]} {hour}:00 · {addDays(date, 56)}까지. 규칙
            관리(삭제)는 예약 화면 하단 "고정 스케줄" 패널에서 할 수 있어요.
          </p>
          <Button className="w-full" onClick={onClose}>
            닫기
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal open onClose={onClose} title="예약 생성 (대행)">
      <div className="space-y-3">
        <div>
          <label className="mb-1 block text-[11px] text-muted">시간</label>
          <Select value={hour} onChange={(e) => setHour(Number(e.target.value))}>
            {hours.map((h) => (
              <option key={h} value={h}>
                {h}:00
              </option>
            ))}
          </Select>
        </div>
        <div>
          <label className="mb-1 block text-[11px] text-muted">회원</label>
          <Select
            value={memberId}
            onChange={(e) => {
              setMemberId(e.target.value);
              setPassId("");
            }}
            disabled={membersQ.isError}
          >
            <option value="">선택하세요</option>
            {(membersQ.data ?? []).map((m) => (
              <option key={m.id} value={m.id}>
                {m.name}
              </option>
            ))}
          </Select>
          {/* 조회 실패를 "회원 0명"으로 위장하지 않는다 — 빈 셀렉트는 "등록된 회원이 없다"로 읽힌다. */}
          {membersQ.isError && (
            <p className="mt-1 text-[10.5px] text-danger">
              회원 목록을 불러오지 못했어요 — 새로고침 후 다시 시도해주세요. ({membersQ.error.message})
            </p>
          )}
        </div>
        <div>
          <label className="mb-1 block text-[11px] text-muted">
            회원권 (패스를 고르면 담당 트레이너가 자동으로 정해집니다)
          </label>
          <Select value={passId} onChange={(e) => setPassId(e.target.value)} disabled={!memberId}>
            <option value="">선택하세요</option>
            {availablePasses.map((p) => (
              <option key={p.id} value={p.id}>
                {p.product} · {staffName(p.trainer_id)} (잔여 {p.remaining})
              </option>
            ))}
          </Select>
          {selectedMember && !availablePasses.length && (
            <p className="mt-1 text-[10.5px] text-danger">사용 가능한(활성·잔여 있음) 회원권이 없습니다.</p>
          )}
          {passTrainerRetired && (
            <p className="mt-1 text-[10.5px] text-warn">
              이 회원권의 담당이 퇴사 처리됐어요 — 설정·직원에서 담당을 이관한 뒤 예약할 수 있어요.
            </p>
          )}
        </div>

        <label className="flex items-center gap-2 text-[12.5px]">
          <input
            type="checkbox"
            checked={repeatWeekly}
            onChange={(e) => setRepeatWeekly(e.target.checked)}
          />
          매주 이 시간 반복 (고정 스케줄로 등록)
        </label>
        {repeatWeekly && (
          <p className="text-[10.5px] text-muted">
            매주 {WEEKDAY_LABEL[dateToWeekday(date)]} {hour}:00 — 종료일 {addDays(date, 56)}(+8주)
            까지, 4주치 선행 예약이 즉시 생성됩니다.
          </p>
        )}
        {/* 선행 생성 창은 오늘 기준 4주 — 그 밖의 날짜에서 반복을 걸면 "이 날짜 회차"는 아직 안 깔린다. */}
        {repeatWeekly && date > addDays(todayStr(), 28) && (
          <p className="text-[10.5px] text-warn">
            반복 등록 시 앞 4주 회차만 우선 생성돼요 — 이 날짜 회차는 이후 자동 생성 대상이에요.
          </p>
        )}

        {error && <p className="text-[11px] text-danger">{error.message}</p>}

        <Button
          className="w-full"
          disabled={!memberId || !passId || pending || passTrainerRetired}
          onClick={submit}
        >
          {repeatWeekly ? <Repeat className="h-4 w-4" /> : <Plus className="h-4 w-4" />}{" "}
          {pending ? "처리 중…" : repeatWeekly ? "고정 스케줄 등록" : "예약 확정"}
        </Button>
      </div>
    </Modal>
  );
}

function ManageBookingModal({
  team,
  slotKey,
  trainerName,
  onClose,
}: {
  team: SlotTeam;
  slotKey: string;
  trainerName: string;
  onClose: () => void;
}) {
  const membersQ = useMembers();
  const { me } = useAuth();
  const complete = useCompleteBooking();
  const noshow = useNoshowBooking();
  const cancel = useCancelBooking();
  // v1.4(P29): 완료 처리 성공 후 모달을 닫지 않고 "수업 기록(선택)" 단계로 전환한다.
  // slots 무효화로 team prop이 갱신되진 않으므로(모달 state에 고정) 단계는 로컬 state로 든다.
  const [recording, setRecording] = useState(false);
  // v1.5: 무차감 취소(운영 사유) — 컷오프 경과 취소여도 노쇼 차감·유예 소진 없이 취소만.
  // 어드민은 스태프 전용 화면이라 역할 게이트 없이 항상 노출한다(member 요청은 서버가 무시).
  const [waiveCancel, setWaiveCancel] = useState(false);
  // 노쇼·취소는 원장을 건드리고 서버에 되돌리는 동사가 없다 — 고정 스케줄 삭제(confirmId)·환불과
  // 같은 2단 확인을 건다. 한 번에 하나만 열린다(다른 확인을 열면 앞의 것이 닫힌다).
  const [confirmAction, setConfirmAction] = useState<"noshow" | "cancel" | null>(null);
  // 트레이너는 본인 수업만 처리 가능(서버도 403으로 막지만 UI에서 사전 차단 — P13).
  const isMine = me?.role !== "trainer" || team.trainer_id === me.uid;
  // 이름을 못 풀면 "예약됨"으로 통일한다 — raw member_id(mem_7Kd2…)를 이름 자리에 노출하지
  // 않는다(개인정보 최소 노출 + 문서ID는 사람이 읽을 정보가 아니다).
  const resolvedName = membersQ.data?.find((m) => m.id === team.member_id)?.name;
  const memberName = resolvedName ?? UNRESOLVED_MEMBER_SLOT;
  // 확인 문구의 주어 — 이름을 못 풀었으면 "예약됨 님"이라고 쓰지 않는다.
  const subject = resolvedName ? `${resolvedName} 님의 예약을` : "이 예약을";
  const status = recording ? "completed" : (team.status ?? "confirmed");
  const busy = complete.isPending || noshow.isPending || cancel.isPending;
  const err = complete.error ?? noshow.error ?? cancel.error;

  return (
    <Modal open onClose={onClose} title="예약 상세">
      <div className="space-y-3 text-sm">
        <div>
          <div className="text-[15px] font-bold">
            {memberName} <span className="text-muted">{KIND_LABEL[team.kind]}</span>
          </div>
          <div className="text-xs text-muted">담당 {trainerName}</div>
        </div>
        <div>
          현재 상태:{" "}
          {status === "completed" && <Badge tone="ok">완료</Badge>}
          {status === "noshow" && <Badge tone="danger">노쇼</Badge>}
          {status === "confirmed" && <Badge tone="warn">예정</Badge>}
        </div>

        {err && <p className="text-[11px] text-danger">{err.message}</p>}

        {status === "confirmed" && !isMine && (
          <p className="text-[11px] text-muted">담당 코치의 수업입니다 — 완료/노쇼/취소는 담당 코치 또는 대표만 처리할 수 있어요.</p>
        )}
        {status === "confirmed" && isMine && (
          <>
            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                disabled={busy}
                onClick={() => complete.mutate(team.booking_id, { onSuccess: () => setRecording(true) })}
              >
                <Check className="h-3.5 w-3.5" /> 완료 처리
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={busy}
                onClick={() => setConfirmAction("noshow")}
              >
                <Ban className="h-3.5 w-3.5" /> 노쇼 처리
              </Button>
              <Button
                size="sm"
                variant="danger"
                disabled={busy}
                onClick={() => setConfirmAction("cancel")}
              >
                <XCircle className="h-3.5 w-3.5" /> 예약 취소
              </Button>
            </div>
            <label className="flex items-center gap-2 text-[11.5px] text-muted">
              <input
                type="checkbox"
                checked={waiveCancel}
                onChange={(e) => setWaiveCancel(e.target.checked)}
                disabled={confirmAction === "cancel"}
              />
              페널티 없이 취소 (운영 사유)
            </label>

            {confirmAction === "noshow" && (
              <div className="rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
                <p className="text-[11.5px] leading-relaxed text-danger">
                  {subject} 노쇼로 처리합니다. 세션 원장에 노쇼 기록이 남고 <b>1회가 차감</b>돼요
                  (센터 정책상 최초 1회는 유예로 기록되며, 그 경우 유예가 소진돼요). 되돌리는
                  기능이 없어요.
                </p>
                <div className="mt-2 flex gap-2">
                  <Button
                    size="sm"
                    variant="danger"
                    disabled={busy}
                    onClick={() => noshow.mutate(team.booking_id, { onSuccess: onClose })}
                  >
                    {noshow.isPending ? "처리 중…" : "노쇼 처리 확정"}
                  </Button>
                  <Button size="sm" variant="ghost" disabled={busy} onClick={() => setConfirmAction(null)}>
                    취소
                  </Button>
                </div>
              </div>
            )}

            {confirmAction === "cancel" && (
              <div className="rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
                <p className="text-[11.5px] leading-relaxed text-danger">
                  {waiveCancel ? (
                    <>
                      {subject} <b>페널티 없이</b> 취소합니다. 세션 차감·유예 소진 없이 예약만
                      사라져요. 취소된 예약은 되돌릴 수 없어요(필요하면 다시 예약해주세요).
                    </>
                  ) : (
                    <>
                      {subject} 취소합니다. 취소 마감(정책 컷오프)이 지난 뒤라면 노쇼와 동일하게{" "}
                      <b>세션 1회가 차감</b>되고 최초 1회 유예가 소진돼요. 되돌릴 수 없어요 —
                      운영 사유라면 "돌아가기"를 누르고 "페널티 없이 취소"를 먼저 체크하세요.
                    </>
                  )}
                </p>
                <div className="mt-2 flex gap-2">
                  <Button
                    size="sm"
                    variant="danger"
                    disabled={busy}
                    onClick={() =>
                      cancel.mutate(
                        { id: team.booking_id, waive: waiveCancel },
                        { onSuccess: onClose },
                      )
                    }
                  >
                    {cancel.isPending ? "처리 중…" : waiveCancel ? "무차감 취소 확정" : "예약 취소 확정"}
                  </Button>
                  <Button size="sm" variant="ghost" disabled={busy} onClick={() => setConfirmAction(null)}>
                    돌아가기
                  </Button>
                </div>
              </div>
            )}
          </>
        )}

        {/* 이미 완료된 팀도 기록을 사후 입력할 수 있다 — 완료 직후 건너뛴 기록의 회수 경로. */}
        {status === "completed" && !recording && isMine && (
          <Button size="sm" variant="outline" onClick={() => setRecording(true)}>
            <Dumbbell className="h-3.5 w-3.5" /> 수업 기록 남기기
          </Button>
        )}

        {recording && <WorkoutLogStep team={team} date={slotKeyToDate(slotKey)} onDone={onClose} />}

        {!recording && (
          <p className="text-[10.5px] text-muted">
            취소 컷오프(정책 기준)를 지나면 노쇼 처리될 수 있어요 — 코치 사정·고정 스케줄 정리
            같은 운영 사유면 "페널티 없이 취소"를 체크하세요(차감 없이 취소만 됩니다). 완료 처리
            시 세션 원장에서 1회 차감됩니다.
          </p>
        )}
      </div>
    </Modal>
  );
}

// 수업 기록(30초 기록, P29·v1.4) — 완료 처리 직후 같은 모달에서 선택 입력. 필수 아님(건너뛰기 가능).
// date = slotKey 파생(YYYY-MM-DD) — 사후 입력이어도 기록은 수업 당일 날짜로 남는다.
function WorkoutLogStep({ team, date, onDone }: { team: SlotTeam; date: string; onDone: () => void }) {
  const [exercises, setExercises] = useState<Exercise[]>([
    { name: "", sets: 3, reps: "", weight_kg: 0, note: "" },
  ]);
  const [coachNote, setCoachNote] = useState("");
  const createLog = useCreateWorkoutLog();

  const named = exercises.filter((ex) => ex.name.trim());
  const canSave = named.length > 0 || coachNote.trim() !== "";

  function save() {
    if (!canSave) return;
    createLog.mutate(
      {
        member_id: team.member_id,
        // 백엔드는 trainer면 본인 명의를 강제하지만, owner가 대신 기록할 땐 trainer_id가 필수다
        // — 예약의 담당 코치 명의로 남긴다.
        trainer_id: team.trainer_id,
        booking_id: team.booking_id,
        // 생략 시 서버가 "오늘"로 기록한다 — 사후 입력이 어제 수업을 오늘 날짜로 남기지 않게
        // 슬롯 날짜를 명시 전송(빈 문자열이면 기존처럼 서버 기본값).
        date: date || undefined,
        exercises: named, // 계약: exercises는 항상 배열
        coach_note: coachNote.trim(),
      },
      { onSuccess: onDone },
    );
  }

  return (
    <div className="rounded-[10px] border border-line bg-panel-2 p-3">
      <div className="mb-0.5 text-[12.5px] font-bold">
        <Check className="mr-1 inline h-3.5 w-3.5 text-ok" />
        완료 처리됐어요 — 수업 기록 남기기 (선택)
      </div>
      <p className="mb-2 text-[10.5px] text-muted">
        30초면 충분해요. 회원 앱 "기록" 탭에 그대로 보입니다 — 건너뛰어도 완료 처리는 유지돼요.
      </p>
      <ExerciseEditor
        exercises={exercises}
        onUpdate={(i, patch) =>
          setExercises((prev) => prev.map((ex, idx) => (idx === i ? { ...ex, ...patch } : ex)))
        }
        onAdd={() =>
          setExercises((prev) => [...prev, { name: "", sets: 3, reps: "", weight_kg: 0, note: "" }])
        }
        onRemove={(i) => setExercises((prev) => prev.filter((_, idx) => idx !== i))}
      />
      <div className="mt-2">
        <Label>코치 코멘트</Label>
        <Input
          value={coachNote}
          onChange={(e) => setCoachNote(e.target.value)}
          placeholder="예: 스쿼트 자세 안정 — 다음엔 무게 +5kg"
        />
      </div>
      {createLog.isError && <p className="mt-2 text-[11px] text-danger">{createLog.error.message}</p>}
      <div className="mt-2.5 flex gap-2">
        <Button size="sm" disabled={!canSave || createLog.isPending} onClick={save}>
          {createLog.isPending ? "저장 중…" : "기록 저장"}
        </Button>
        <Button size="sm" variant="ghost" disabled={createLog.isPending} onClick={onDone}>
          건너뛰기
        </Button>
      </div>
    </div>
  );
}

// 고정 스케줄 관리 패널(P47·v1.4) — 접이식. 목록 조회는 열었을 때만(닫힌 화면의 불필요 호출 방지).
function RecurringPanel({ hours }: { hours: number[] }) {
  const [open, setOpen] = useState(false);
  const { me } = useAuth();
  return (
    <div className="mt-3 rounded-[13px] border border-line bg-panel p-3.5">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center justify-between text-left"
        aria-expanded={open}
      >
        <span className="flex items-center gap-1.5 text-[13px] font-bold">
          <Repeat className="h-4 w-4 text-brand" /> 고정 스케줄 (매주 반복)
        </span>
        {open ? (
          <ChevronDown className="h-4 w-4 text-muted" />
        ) : (
          <ChevronRight className="h-4 w-4 text-muted" />
        )}
      </button>
      {open && <RecurringPanelBody hours={hours} isTrainer={me?.role === "trainer"} />}
    </div>
  );
}

function RecurringPanelBody({ hours, isTrainer }: { hours: number[]; isTrainer: boolean }) {
  // v2.3: include_expired=true. 서버는 until이 지난 규칙을 기본 목록에서 숨기는데, 숨기기만
  // 하면 관리 UI에서 **지울 방법이 없어** 유령 규칙이 쌓인다(그래서 서버가 이 문을 열어 뒀다).
  // 대신 행에 "만료" 배지를 달고 아래로 내려 살아있는 규칙과 섞이지 않게 한다.
  const recurringsQ = useRecurrings(true);
  const membersQ = useMembers();
  const staffQ = useStaff();
  // 삭제 확인 문구에 "몇 건이 함께 취소되는지"를 미리 적기 위한 근거. 패널을 편 순간에만 켜진다
  // (접힌 화면에서 센터 전체 예약을 끌어올 이유가 없다). owner=센터 전체 / trainer=본인 분만으로
  // 규칙 목록과 같은 서버 스코프라 두 숫자가 어긋나지 않는다.
  const bookingsQ = useBookings(todayStr());
  const deleteRecurring = useDeleteRecurring();
  const [confirmId, setConfirmId] = useState<string | null>(null);
  // ?keep_bookings=true 옵트아웃 — "규칙만 끊고 이미 잡힌 회차는 진행"(회원과 이미 합의된 일정)이
  // 실제 운영에 있어 서버가 일부러 열어 둔 길. 확인을 열고 닫을 때마다 초기화한다 — 앞 규칙에서
  // 켠 선택이 다음 규칙의 삭제에 따라붙으면 그게 곧 다음 사고다.
  const [keepBookings, setKeepBookings] = useState(false);

  const memberName = (id: string) =>
    membersQ.data?.find((m) => m.id === id)?.name ?? UNRESOLVED_MEMBER_ROW;
  // 기존 데이터 표시 — 퇴사자도 계속 해석하되 "(퇴사)"를 붙인다(계약 v2.0).
  const staffName = (uid: string) => {
    const s = staffQ.data?.find((x) => x.uid === uid);
    return s ? staffLabel(s) : UNRESOLVED_STAFF;
  };

  // 만료 규칙은 목록 아래로(정렬은 안정적이라 그 안의 기존 순서는 유지된다).
  const rows = useMemo(() => {
    const today = todayStr();
    return (recurringsQ.data ?? [])
      .map((r) => ({ r, expired: !!r.until && r.until < today }))
      .sort((a, b) => Number(a.expired) - Number(b.expired));
  }, [recurringsQ.data]);
  const expiredCount = rows.filter((row) => row.expired).length;

  // 서버 DeleteRecurring과 같은 판정: 이 규칙이 만든 confirmed 예약 중 **아직 시작 전**인 것.
  // 예약 목록이 없으면(로딩·실패) null — 0으로 단정하지 않는다. "0건 취소"는 거짓 안심이고,
  // 지금 고치는 결함이 정확히 그 종류(사실과 다른 확언)다.
  const futureBookingCount = (id: string): number | null => {
    if (!bookingsQ.data) return null;
    const now = Date.now();
    return bookingsQ.data.filter(
      (b) =>
        b.recurring_id === id &&
        b.status === "confirmed" &&
        (slotKeyStart(b.slot_key)?.getTime() ?? 0) > now,
    ).length;
  };

  function openConfirm(id: string) {
    setConfirmId(id);
    setKeepBookings(false);
    deleteRecurring.reset(); // 앞 삭제의 결과 문구가 새 확인 위에 남지 않게
  }
  function closeConfirm() {
    setConfirmId(null);
    setKeepBookings(false);
  }

  const target = rows.find(({ r }) => r.id === confirmId);
  const targetCount = target ? futureBookingCount(target.r.id) : null;
  const result = deleteRecurring.data;

  return (
    <div className="mt-3">
      {(membersQ.isError || staffQ.isError) && (
        <p className="mb-2 text-[10.5px] text-warn">
          {membersQ.isError && staffQ.isError
            ? "회원·직원 목록을 불러오지 못해 아래 표의 이름이 비어 보여요."
            : membersQ.isError
              ? "회원 목록을 불러오지 못해 아래 표의 회원명이 비어 보여요."
              : "직원 목록을 불러오지 못해 아래 표의 담당이 비어 보여요."}
        </p>
      )}
      {bookingsQ.isError && (
        <p className="mb-2 text-[10.5px] text-warn">
          예약 목록을 불러오지 못해 "예정 회차" 건수를 셀 수 없어요 — 삭제하면 몇 건이 함께
          취소되는지 미리 알려드릴 수 없으니, 새로고침 후 다시 열어주세요.
        </p>
      )}
      {recurringsQ.isLoading ? (
        <Spinner />
      ) : recurringsQ.isError ? (
        <ErrorState error={recurringsQ.error} />
      ) : !rows.length ? (
        <EmptyState>등록된 고정 스케줄이 없습니다.</EmptyState>
      ) : (
        <Table>
          <THead>
            <TR>
              <TH>회원</TH>
              <TH>요일</TH>
              <TH>시각</TH>
              <TH>종료일</TH>
              <TH>담당</TH>
              <TH>예정 회차</TH>
              <TH></TH>
            </TR>
          </THead>
          <tbody>
            {rows.map(({ r, expired }) => {
              const count = futureBookingCount(r.id);
              return (
                <TR key={r.id} className={confirmId === r.id ? "bg-danger/[0.06]" : undefined}>
                  <TD className={expired ? "font-bold text-muted" : "font-bold"}>
                    {memberName(r.member_id)}
                  </TD>
                  <TD>{r.days.map((d) => WEEKDAY_LABEL[d]).join(" · ")}</TD>
                  <TD>{r.hour}:00</TD>
                  <TD className="text-muted">
                    ~{r.until}{" "}
                    {expired && (
                      <Badge tone="muted" className="ml-0.5">
                        만료
                      </Badge>
                    )}
                  </TD>
                  <TD>{staffName(r.trainer_id)}</TD>
                  {/* 삭제 시 함께 취소될 건수 — 누르기 전에 보이는 것이 확인 문구보다 먼저다. */}
                  <TD className={count ? "font-bold text-warn" : "text-muted"}>
                    {count === null ? (bookingsQ.isLoading ? "…" : "?") : count === 0 ? "—" : `${count}건`}
                  </TD>
                  <TD>
                    {confirmId === r.id ? (
                      <span className="text-[10.5px] font-extrabold text-danger">확인 중 ↓</span>
                    ) : (
                      <Button size="sm" variant="outline" onClick={() => openConfirm(r.id)}>
                        <Trash2 className="h-3 w-3" /> 삭제
                      </Button>
                    )}
                  </TD>
                </TR>
              );
            })}
          </tbody>
        </Table>
      )}

      {/* 파괴적 액션 확인(confirmId 패턴) — 문구가 서버 동작(v2.3)과 한 글자도 어긋나면 안 된다.
          종전 문구는 "규칙만 삭제됩니다 — 선행 예약은 남아 있어요"였고, 그 말을 믿고 지운 대표는
          회원 4주치가 통보 없이 사라진 뒤 회원 전화로 알게 됐다. */}
      {target && (
        <div className="mt-2 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
          <p className="text-[11.5px] leading-relaxed text-danger">
            <b>{memberName(target.r.member_id)}</b> 님의 매주{" "}
            {target.r.days.map((d) => WEEKDAY_LABEL[d]).join("·")} {target.r.hour}:00 고정 스케줄을
            삭제합니다.{" "}
            {targetCount === null ? (
              <>
                예정 회차 수를 {bookingsQ.isLoading ? "세는 중이에요" : "확인하지 못했어요"} —
                삭제하면 이 규칙이 만든 <b>앞으로의 예약이 함께 취소</b>돼요(무차감이라 회원의 노쇼
                유예는 소진되지 않고, 지난 회차는 기록으로 남아요). 건수를 확인하고 진행하려면
                새로고침 후 다시 열어주세요.
              </>
            ) : targetCount === 0 ? (
              <>
                {target.expired
                  ? `종료일(${target.r.until})이 지난 규칙이라 앞으로 잡힌 회차가 없어요.`
                  : "앞으로 잡힌 회차가 없어 함께 취소될 예약도 없어요."}{" "}
                규칙만 정리되고 지난 회차는 기록으로 그대로 남아요.
              </>
            ) : keepBookings ? (
              <>
                이미 잡힌 <b>예정 {targetCount}건은 그대로 두고</b> 규칙만 끊어요 — 앞으로 새 회차가
                자동으로 깔리지 않을 뿐, 잡힌 회차는 예정대로 진행돼요.
              </>
            ) : (
              <>
                이미 잡힌 <b>예정 {targetCount}건이 함께 취소</b>돼요. 취소는 <b>무차감</b>이라
                회원의 세션·노쇼 유예는 줄지 않지만, 회원 앱에서도 그대로 사라지고 되돌리는 기능이
                없어요(다시 잡으려면 한 건씩 예약해야 해요). 지난 회차는 기록으로 남아요.{" "}
                <b>회원에게 자동으로 알려주는 기능이 없으니 직접 연락해주세요.</b>
              </>
            )}
          </p>
          {/* 옵트아웃은 취소될 회차가 있을 때만 의미가 있다(0건이면 고를 게 없다). */}
          {(targetCount === null || targetCount > 0) && (
            <label className="mt-2 flex items-center gap-2 text-[11.5px] text-danger">
              <input
                type="checkbox"
                checked={keepBookings}
                onChange={(e) => setKeepBookings(e.target.checked)}
                disabled={deleteRecurring.isPending}
              />
              이미 잡힌 회차는 그대로 두기 (규칙만 끊기)
            </label>
          )}
          <div className="mt-2 flex gap-2">
            <Button
              size="sm"
              variant="danger"
              disabled={deleteRecurring.isPending}
              onClick={() =>
                deleteRecurring.mutate(
                  { id: target.r.id, keepBookings },
                  { onSuccess: closeConfirm },
                )
              }
            >
              {deleteRecurring.isPending
                ? "삭제 중…"
                : keepBookings
                  ? "규칙만 삭제 확정"
                  : "삭제 확정"}
            </Button>
            <Button size="sm" variant="ghost" disabled={deleteRecurring.isPending} onClick={closeConfirm}>
              돌아가기
            </Button>
          </div>
        </div>
      )}

      {/* 삭제 결과(200 {cancelled, kept}) — 대표가 회원에게 알릴 근거는 이 숫자뿐이다. */}
      {deleteRecurring.isSuccess && result && (
        <p className="mt-1.5 text-[11px] leading-relaxed text-ok">
          <Check className="mr-1 inline h-3 w-3" />
          {result.cancelled > 0 ? (
            <>
              고정 스케줄을 삭제했어요 — 예정 예약 <b>{result.cancelled}건</b>을 함께 취소했어요
              (무차감).
              {result.kept > 0 && ` 지난 ${result.kept}건은 그대로 뒀어요.`} 회원에게는 대표가 직접
              알려주세요.
            </>
          ) : result.kept > 0 ? (
            <>
              고정 스케줄을 삭제했어요 — 예약 <b>{result.kept}건</b>은 그대로 뒀어요(취소된 예약
              없음).
            </>
          ) : (
            <>고정 스케줄을 삭제했어요 — 함께 정리된 예약은 없었어요.</>
          )}
        </p>
      )}
      {deleteRecurring.isError && (
        <p className="mt-1 text-[11px] text-danger">삭제 실패: {deleteRecurring.error.message}</p>
      )}
      <p className="mt-2 text-[10.5px] leading-relaxed text-muted">
        {isTrainer
          ? "내 담당 고정 스케줄만 표시됩니다(서버 스코프)."
          : "센터 전체 고정 스케줄입니다 — 트레이너 계정에는 본인 것만 보여요."}{" "}
        삭제하면 그 규칙이 만든 <b>앞으로의 예약도 함께 취소</b>됩니다(무차감 · 지난 회차는 보존).
        {expiredCount > 0 && ` 기간이 끝난 규칙 ${expiredCount}건도 함께 표시돼요 — 여기서 정리할 수 있어요.`}
      </p>

      <NewRecurringForm hours={hours} />
    </div>
  );
}

function NewRecurringForm({ hours }: { hours: number[] }) {
  const membersQ = useMembers();
  const staffQ = useStaff();
  const createRecurring = useCreateRecurring();

  const [memberId, setMemberId] = useState("");
  const [passId, setPassId] = useState("");
  const [days, setDays] = useState<Set<Weekday>>(new Set());
  const [hour, setHour] = useState(hours[0] ?? 10);
  const [until, setUntil] = useState(addDays(todayStr(), 56)); // +8주 기본

  const WEEKDAYS: Weekday[] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  // 기존 데이터 표시 — 퇴사자도 계속 해석하되 "(퇴사)"를 붙인다(계약 v2.0).
  const staffName = (uid: string) => {
    const s = staffQ.data?.find((x) => x.uid === uid);
    return s ? staffLabel(s) : UNRESOLVED_STAFF;
  };
  const selectedMember = membersQ.data?.find((m) => m.id === memberId);
  // 서버 BookableStatus와 같은 판정 — scheduled(시작 전 재등록)도 선예약 대상이다.
  const availablePasses = (selectedMember?.passes ?? []).filter(
    (p) => isPassBookable(p) && p.remaining > 0,
  );
  const selectedPass = availablePasses.find((p) => p.id === passId);
  // 담당이 퇴사 처리된 패스는 서버가 400으로 막는다(POST /v1/recurrings도 예약과 같은 규칙).
  const passTrainerRetired =
    !!selectedPass && !isStaffActive(staffQ.data?.find((s) => s.uid === selectedPass.trainer_id));
  // until이 과거면 생성될 회차가 0개 — 서버 왕복 전에 차단(date min과 이중 방어).
  const canSubmit =
    !!memberId &&
    !!selectedPass &&
    !passTrainerRetired &&
    days.size > 0 &&
    !!until &&
    until >= todayStr();

  function toggleDay(d: Weekday) {
    setDays((prev) => {
      const next = new Set(prev);
      if (next.has(d)) next.delete(d);
      else next.add(d);
      return next;
    });
  }

  function submit() {
    if (!canSubmit || !selectedPass) return;
    createRecurring.mutate(
      {
        member_id: memberId,
        trainer_id: selectedPass.trainer_id, // 패스가 담당을 결정(설계03 R4)
        pass_id: selectedPass.id,
        days: Array.from(days),
        hour,
        until,
      },
      {
        onSuccess: () => {
          setMemberId("");
          setPassId("");
          setDays(new Set());
        },
      },
    );
  }

  return (
    <div className="mt-3 rounded-[10px] border border-line bg-panel-2 p-3">
      <div className="mb-2 text-[11.5px] font-bold">새 고정 스케줄</div>
      <div className="grid gap-2 sm:grid-cols-2">
        <div>
          <Label>회원</Label>
          <Select
            value={memberId}
            onChange={(e) => {
              setMemberId(e.target.value);
              setPassId("");
            }}
            disabled={membersQ.isError}
          >
            <option value="">선택하세요</option>
            {(membersQ.data ?? []).map((m) => (
              <option key={m.id} value={m.id}>
                {m.name}
              </option>
            ))}
          </Select>
          {membersQ.isError && (
            <p className="mt-1 text-[10.5px] text-danger">
              회원 목록을 불러오지 못했어요 — 새로고침 후 다시 시도해주세요.
            </p>
          )}
        </div>
        <div>
          <Label>회원권 (담당 트레이너 자동)</Label>
          <Select value={passId} onChange={(e) => setPassId(e.target.value)} disabled={!memberId}>
            <option value="">선택하세요</option>
            {availablePasses.map((p) => (
              <option key={p.id} value={p.id}>
                {p.product} · {staffName(p.trainer_id)} (잔여 {p.remaining})
              </option>
            ))}
          </Select>
          {passTrainerRetired && (
            <p className="mt-1 text-[10.5px] text-warn">
              담당이 퇴사 처리된 회원권이에요 — 설정·직원에서 담당을 이관한 뒤 등록할 수 있어요.
            </p>
          )}
        </div>
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-1.5 text-[11.5px]">
        <span className="text-muted">요일:</span>
        {WEEKDAYS.map((d) => (
          <Chip key={d} active={days.has(d)} onClick={() => toggleDay(d)}>
            {WEEKDAY_LABEL[d]}
          </Chip>
        ))}
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-2 text-[11.5px]">
        <span className="text-muted">시각:</span>
        <Select value={hour} onChange={(e) => setHour(Number(e.target.value))} className="w-auto">
          {hours.map((h) => (
            <option key={h} value={h}>
              {h}:00
            </option>
          ))}
        </Select>
        <span className="text-muted">종료일:</span>
        <Input
          type="date"
          value={until}
          min={todayStr()}
          onChange={(e) => setUntil(e.target.value)}
          className="w-auto"
        />
      </div>
      {until && until < todayStr() && (
        <p className="mt-1 text-[10.5px] text-warn">종료일은 오늘 이후여야 등록할 수 있어요.</p>
      )}

      {createRecurring.isSuccess && (
        <p className="mt-2 text-[11px] text-ok">
          <Check className="mr-1 inline h-3 w-3" />
          규칙 등록 완료 — 앞으로 4주 안의 회차가 자동 예약됐어요.
        </p>
      )}
      {createRecurring.isError && (
        <p className="mt-2 text-[11px] text-danger">{createRecurring.error.message}</p>
      )}

      <Button
        size="sm"
        className="mt-2.5"
        disabled={!canSubmit || createRecurring.isPending}
        onClick={submit}
      >
        <Repeat className="h-3.5 w-3.5" /> {createRecurring.isPending ? "등록 중…" : "고정 스케줄 등록"}
      </Button>
      <p className="mt-2 text-[10.5px] text-muted">
        등록 즉시 4주치 선행 예약이 깔립니다(잔여 세션·유효기간 이내). 특정 회차가 용량·휴무와
        겹치면 그 회차만 건너뜁니다.
      </p>
    </div>
  );
}

// 운동 항목 에디터 — Homework ItemsEditor 패턴 재사용(필드만 Exercise 규약: 세트·횟수·무게kg·메모).
function ExerciseEditor({
  exercises,
  onUpdate,
  onAdd,
  onRemove,
}: {
  exercises: Exercise[];
  onUpdate: (i: number, patch: Partial<Exercise>) => void;
  onAdd: () => void;
  onRemove: (i: number) => void;
}) {
  return (
    <div className="space-y-1.5">
      {exercises.map((ex, i) => (
        <div key={i} className="grid grid-cols-[1fr_54px_70px_64px_1fr_28px] items-center gap-1.5">
          <Input
            value={ex.name}
            onChange={(e) => onUpdate(i, { name: e.target.value })}
            placeholder="운동명(예: 스쿼트)"
          />
          <Input
            type="number"
            min={0}
            value={ex.sets || ""}
            // 음수 차단 — min 속성은 타이핑(-3)을 못 막는다. 0 미만은 0으로 클램프.
            onChange={(e) => onUpdate(i, { sets: Math.max(0, Number(e.target.value) || 0) })}
            placeholder="세트"
          />
          <Input
            value={ex.reps}
            onChange={(e) => onUpdate(i, { reps: e.target.value })}
            placeholder="12 / 30초"
          />
          <Input
            type="number"
            min={0}
            step={0.5}
            value={ex.weight_kg || ""}
            onChange={(e) => onUpdate(i, { weight_kg: Math.max(0, Number(e.target.value) || 0) })}
            placeholder="kg"
            title="무게(kg) — 자중이면 비워두세요(0)"
          />
          <Input
            value={ex.note}
            onChange={(e) => onUpdate(i, { note: e.target.value })}
            placeholder="메모"
          />
          <button
            onClick={() => onRemove(i)}
            className="flex h-8 w-7 items-center justify-center rounded-lg text-muted hover:bg-panel-2 hover:text-danger"
            aria-label="운동 항목 삭제"
          >
            <Trash2 className="h-3.5 w-3.5" />
          </button>
        </div>
      ))}
      <Button size="sm" variant="outline" onClick={onAdd}>
        <Plus className="h-3.5 w-3.5" /> 운동 추가
      </Button>
    </div>
  );
}
