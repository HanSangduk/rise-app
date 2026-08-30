// TanStack Query 훅 — 서버상태(백엔드 API)를 클라이언트상태와 분리.
// 각 훅은 src/lib/api.ts의 메서드 1:1 래핑 + 캐시 무효화 규칙만 담당한다.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiError, api } from "./api";
import type {
  CenterBusiness,
  CenterFacility,
  CenterPolicy,
  CreateStaffRequest,
  Exercise,
  HomeworkCreateRequest,
  InbodyCreateRequest,
  Member,
  PaymentCreateRequest,
  StaffPhotoUploadRequest,
  StaffProfile,
  StaffUpdateRequest,
  Weekday,
} from "./types";

export const keys = {
  members: (trainer?: string, q?: string) => ["members", trainer ?? "", q ?? ""] as const,
  memberLedger: (id: string, pass?: string) => ["memberLedger", id, pass ?? ""] as const,
  contracts: (member?: string, status?: string) => ["contracts", member ?? "", status ?? ""] as const,
  // "" = 전체 조회(v1.5 — member 생략) · 회원 id = 해당 회원만.
  payments: (member?: string) => ["payments", member ?? ""] as const,
  slots: (date: string) => ["slots", date] as const,
  // from = "YYYY-MM-DD" 이후(포함) 예약. slots(날짜별 그리드)와 다른 축이라 키를 분리한다.
  bookings: (from?: string) => ["bookings", from ?? ""] as const,
  // v2.3: include_expired 여부로 응답 집합이 달라져 키를 가른다(같은 키에 두 목록을 겹쳐 담으면
  // 만료 포함 목록이 기본 목록을 덮어 다른 화면에 만료 규칙이 새어 나간다).
  recurrings: (includeExpired?: boolean) => ["recurrings", includeExpired ? "all" : ""] as const,
  workoutLogs: (member?: string) => ["workoutLogs", member ?? ""] as const,
  homeworks: (member?: string) => ["homeworks", member ?? ""] as const,
  hwChecks: (hwId: string) => ["hwChecks", hwId] as const,
  stats: (range: string, scope: string) => ["stats", range, scope] as const,
  bodyPhotos: (member: string) => ["bodyPhotos", member] as const,
  inbody: (member: string) => ["inbody", member] as const,
  staff: ["staff"] as const,
  center: ["center"] as const,
  // keys.center와 **가르는** 이유: GET /v1/center은 member까지 읽는 공개 조회고 이쪽은 owner
  // 전용 비밀이다. 같은 키에 담으면 대표가 QR을 재발급할 때마다 정책·사업자 정보까지 다시
  // 읽히고, 반대로 정책을 저장할 때마다 토큰 조회가 딸려 나간다(서로 무관한 두 문서다).
  checkinQr: ["checkinQr"] as const,
  joinRequests: ["joinRequests"] as const,
  consultRequests: ["consultRequests"] as const,
};

// ── 회원 · 회원권 ──────────────────────────────────────────────────────
export function useMembers(trainer?: string, q?: string) {
  return useQuery({
    queryKey: keys.members(trainer, q),
    queryFn: () => api.members({ trainer, q }),
  });
}

export function useCreateMember() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (m: Partial<Member>) => api.createMember(m),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["members"] }),
  });
}

export function useUpdateMember() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: Partial<Member> }) => api.updateMember(id, patch),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["members"] }),
  });
}

export function useMemberLedger(id: string | null, pass?: string) {
  return useQuery({
    queryKey: keys.memberLedger(id ?? "", pass),
    queryFn: () => api.memberLedger(id!, pass),
    enabled: !!id,
  });
}

export function useHoldPass() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: { from: string; to: string; reason: string } }) =>
      api.holdPass(id, body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["members"] });
      // 홀딩은 원장(hold) 기록을 남긴다 — 회원 상세 원장도 최신화.
      qc.invalidateQueries({ queryKey: ["memberLedger"] });
    },
  });
}

export function useResumePass() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.resumePass(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["members"] });
      // 재개는 원장(resume) 기록을 남긴다.
      qc.invalidateQueries({ queryKey: ["memberLedger"] });
    },
  });
}

// 환불 계산기 — GET성 조회지만 계약상 POST(used 파라미터)라 뮤테이션으로 다룸(부작용 없음).
export function useRefundQuote() {
  return useMutation({
    mutationFn: ({ id, used }: { id: string; used: number }) => api.refundQuote(id, used),
  });
}

// 환불 실행(v1.4, owner 전용) — 원장 refund(잔여 0 마감) + status=refunded 전이.
// 환불은 원장·패스 상태를 바꾼다: 회원(임베드 passes)·원장·결제 목록을 모두 최신화.
// v1.5: 미납 회차 청구 종결(waived_at)·미서명 계약 자동 무효(voided)·순매출/미수금 재계산까지
// 일어난다 — 계약 목록과 stats(미수금 KPI·매출)도 함께 무효화한다.
export function useRefundPass() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, used }: { id: string; used: number }) => api.refundPass(id, used),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["members"] });
      qc.invalidateQueries({ queryKey: ["memberLedger"] });
      qc.invalidateQueries({ queryKey: ["payments"] });
      qc.invalidateQueries({ queryKey: ["contracts"] });
      qc.invalidateQueries({ queryKey: ["stats"] });
      // 환불은 해당 패스의 미래 예약을 일괄 취소한다 — 스케줄 그리드(slots)가 stale로 남지 않게.
      qc.invalidateQueries({ queryKey: ["slots"] });
    },
  });
}

// ── 계약(전자계약) · 결제(v1.1 정합 패치) — 추가결제 원스톱 플로우 ─────────
// 회원권 발급(useCreatePass) → 계약 자동 생성(sent) → 결제 기록(useCreatePayment, 분할 가능).
export function useCreatePass() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: {
      member_id: string;
      trainer_id: string;
      product: string;
      paid_amount: number;
      total_sessions: number;
      valid_from: string;
      valid_until: string;
    }) => api.createPass(p),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["members"] });
      // 발급은 서명 대기(sent) 계약을 **서버가 함께 생성**한다(service.buildContractForPass — v2.6 IssuePass 트랜잭션).
      // 계약 캐시를 비우지 않으면 회원권만 뜨고 계약은 안 보여서, 결제 기록이 실패해 모달이
      // 열린 채로 끝났을 때 대표가 "추가 계약"을 다시 눌러 같은 회원권을 이중 발급한다
      // (v1.5의 "결제 기록 없는 회원권" 경고가 막으려던 바로 그 시나리오).
      qc.invalidateQueries({ queryKey: ["contracts"] });
    },
  });
}

export function useContracts(member?: string, status?: string) {
  return useQuery({
    queryKey: keys.contracts(member, status),
    queryFn: () => api.contracts({ member, status }),
  });
}

// P40: onSent — 발송 성공 표식(호출부의 세션 로컬 Set) 갱신용 **훅-레벨** 콜백. mutate-레벨
// onSuccess는 같은 훅에서 다음 mutate()가 시작되는 순간 옵저버가 앞선 mutation에서 떨어져
// 영영 실행되지 않는다(react-query v5) — 연속 발송에서 앞선 건이 성공하고도 마킹을 잃었다.
// 훅-레벨(useMutation 옵션)은 옵저버 분리와 무관하게 mutation마다 실행되므로, 캐시 무효화와
// 같은 자리에서 variables(계약 id)로 어느 건이 성공했는지 식별해 마킹한다.
export function useSendContract(onSent?: (id: string) => void) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.sendContract(id),
    onSuccess: (_data, id) => {
      qc.invalidateQueries({ queryKey: ["contracts"] });
      onSent?.(id);
    },
  });
}

// member: 회원 id = 해당 회원 결제만 · undefined(인자 생략) = 전체 조회(v1.5 — 대시보드
// "결제 기록 없는 회원권" 집계) · null = 아직 대상 미정(조회 비활성).
export function usePayments(member?: string | null) {
  return useQuery({
    queryKey: keys.payments(member ?? ""),
    queryFn: () => api.payments(member ?? undefined),
    enabled: member !== null,
  });
}

export function useCreatePayment() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: PaymentCreateRequest) => api.createPayment(p),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["payments"] });
      // v1.1: "발급 시 자동 생성 가능" — 결제 기록 직후 계약·회원권(임베드 passes) 목록도 최신화.
      qc.invalidateQueries({ queryKey: ["contracts"] });
      qc.invalidateQueries({ queryKey: ["members"] });
      // v1.5: 분할 미납 회차는 미수금 KPI(unpaid/upcoming)에 바로 잡힌다 — 통계도 즉시 갱신.
      qc.invalidateQueries({ queryKey: ["stats"] });
    },
  });
}

export function usePayInstallment() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ paymentId, index }: { paymentId: string; index: number }) =>
      api.payInstallment(paymentId, index),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["payments"] });
      // v1.5: 납부 처리는 미수금 KPI(연체·미도래)를 줄인다 — 매출·통계 즉시 갱신.
      qc.invalidateQueries({ queryKey: ["stats"] });
    },
  });
}

// ── 예약 · 슬롯 ────────────────────────────────────────────────────────
export function useSlots(date: string) {
  return useQuery({ queryKey: keys.slots(date), queryFn: () => api.slots(date) });
}

// 예약 목록(GET /v1/bookings) — 퇴사 blockers의 예약 id를 회원 이름·시각으로 풀 때만 쓴다.
// 그 화면에 들어가기 전에는 켜지 않는다(enabled=false) — 상시 전체 예약을 끌어올 이유가 없다.
export function useBookings(from?: string, enabled = true) {
  return useQuery({
    queryKey: keys.bookings(from),
    queryFn: () => api.bookings({ from }),
    enabled,
  });
}

export function useCreateBooking() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: { slot_key: string; member_id: string; pass_id: string }) => api.createBooking(body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["slots"] });
      qc.invalidateQueries({ queryKey: ["members"] });
    },
  });
}

// v1.5: waive=true — 스태프의 무차감 취소(운영 사유). 일반 취소는 컷오프 경과 시 노쇼 차감이
// 일어날 수 있어(원장 기록) 회원·원장 캐시도 함께 무효화한다.
export function useCancelBooking() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, waive }: { id: string; waive?: boolean }) => api.cancelBooking(id, { waive }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["slots"] });
      qc.invalidateQueries({ queryKey: ["members"] });
      qc.invalidateQueries({ queryKey: ["memberLedger"] });
    },
  });
}

export function useCompleteBooking() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.completeBooking(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["slots"] });
      qc.invalidateQueries({ queryKey: ["members"] });
      // 완료는 원장(complete, -1) 기록을 남긴다.
      qc.invalidateQueries({ queryKey: ["memberLedger"] });
    },
  });
}

export function useNoshowBooking() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.noshowBooking(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["slots"] });
      qc.invalidateQueries({ queryKey: ["members"] });
      // 노쇼는 원장(noshow 또는 noshow_waived) 기록을 남긴다.
      qc.invalidateQueries({ queryKey: ["memberLedger"] });
    },
  });
}

// P40: onCheckedIn — 체크인 성공 표식(대시보드 세션 로컬 Set) 갱신용 훅-레벨 콜백.
// useSendContract와 같은 결함·같은 수리 — mutate-레벨 onSuccess는 연속 체크인에서 옵저버가
// 떨어져 앞선 건의 마킹이 유실된다. booking_id 없는 변형(self_qr)은 마킹 대상이 아니라 건너뛴다.
export function useCheckin(onCheckedIn?: (bookingId: string) => void) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: { source: "tap" | "self_qr"; booking_id?: string; qr_token?: string }) =>
      api.checkin(body),
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ["slots"] });
      // 체크인은 출석 기록 + last_visit_at 갱신만 한다 — 세션 차감(원장 complete)은
      // 완료 처리(useCompleteBooking)의 몫이라 원장은 무효화하지 않는다.
      qc.invalidateQueries({ queryKey: ["members"] });
      if (vars.booking_id) onCheckedIn?.(vars.booking_id);
    },
  });
}

// ── 고정 스케줄(P47 · v1.4 관리 UI) ────────────────────────────────────
// includeExpired(v2.3): 만료(until 경과) 규칙까지 받아온다. 관리 패널은 true로 부른다 —
// 서버 기본값(숨김)만 쓰면 만료 규칙이 목록에 없어 **지울 수단 자체가 없다**.
export function useRecurrings(includeExpired = false) {
  return useQuery({
    queryKey: keys.recurrings(includeExpired),
    queryFn: () => api.recurrings({ includeExpired }),
  });
}

export function useCreateRecurring() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: {
      member_id: string;
      trainer_id: string;
      pass_id: string;
      days: Weekday[];
      hour: number;
      until: string;
    }) => api.createRecurring(body),
    onSuccess: () => {
      // 생성 즉시 4주치 선행 예약이 깔린다 — 그리드(slots)·예약 목록·규칙 목록 모두 최신화.
      qc.invalidateQueries({ queryKey: ["slots"] });
      qc.invalidateQueries({ queryKey: ["bookings"] });
      qc.invalidateQueries({ queryKey: ["recurrings"] });
    },
  });
}

// v2.3: 규칙 해제는 그 규칙이 만든 **미래 confirmed 예약을 함께 취소**한다(keepBookings=true면
// 예약을 남긴다). 그래서 규칙 목록뿐 아니라 슬롯 그리드와 예약 목록도 함께 흔들린다 —
// 예약 목록은 "이 규칙이 몇 건을 데려가는지" 사전 집계의 근거라 남겨 두면 방금 취소한 건을
// 다시 세어 보여준다. 원장·잔여는 무차감 취소라 바뀌지 않으므로 무효화 대상이 아니다.
export function useDeleteRecurring() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, keepBookings }: { id: string; keepBookings?: boolean }) =>
      api.deleteRecurring(id, { keepBookings }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["slots"] });
      qc.invalidateQueries({ queryKey: ["bookings"] });
      qc.invalidateQueries({ queryKey: ["recurrings"] });
    },
  });
}

// ── 수업 기록(WorkoutLog, v1.4) ────────────────────────────────────────
export function useWorkoutLogs(memberId: string | null) {
  return useQuery({
    queryKey: keys.workoutLogs(memberId ?? ""),
    queryFn: () => api.workoutLogs(memberId!),
    enabled: !!memberId,
  });
}

export function useCreateWorkoutLog() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: {
      member_id: string;
      trainer_id?: string;
      booking_id?: string;
      date?: string;
      title?: string;
      exercises: Exercise[];
      coach_note: string;
    }) => api.createWorkoutLog(body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["workoutLogs"] }),
  });
}

// ── Home Work ──────────────────────────────────────────────────────────
export function useHomeworks(member?: string) {
  return useQuery({ queryKey: keys.homeworks(member), queryFn: () => api.homeworks(member) });
}

export function useCreateHomework() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (h: HomeworkCreateRequest) => api.createHomework(h),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["homeworks"] }),
  });
}

export function useHwChecks(hwId: string | null) {
  return useQuery({
    queryKey: keys.hwChecks(hwId ?? ""),
    queryFn: () => api.hwChecks(hwId!),
    enabled: !!hwId,
  });
}

// ── 통계 ───────────────────────────────────────────────────────────────
export function useStats(range: string, scope: "me" | "center") {
  return useQuery({ queryKey: keys.stats(range, scope), queryFn: () => api.stats(range, scope) });
}

// ── 체형 분석 · 인바디 ─────────────────────────────────────────────────
export function useBodyPhotos(member: string | null) {
  return useQuery({
    queryKey: keys.bodyPhotos(member ?? ""),
    queryFn: () => api.bodyPhotos(member!),
    enabled: !!member,
  });
}

export function useInbodyList(member: string | null) {
  return useQuery({
    queryKey: keys.inbody(member ?? ""),
    queryFn: () => api.inbody(member!),
    enabled: !!member,
  });
}

export function useCreateInbody() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (b: InbodyCreateRequest) => api.createInbody(b),
    onSuccess: (_data, vars) => qc.invalidateQueries({ queryKey: keys.inbody(vars.member_id) }),
  });
}

// [v2.9] 인바디 삭제 — 목록 캐시가 회원 단위 키(keys.inbody(member))라 memberId를 함께 받아
// 그 회원 것만 무효화한다(레코드의 member_id를 호출부가 그대로 넘기면 된다).
export function useDeleteInbody() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id }: { id: string; memberId: string }) => api.deleteInbody(id),
    onSuccess: (_data, vars) => qc.invalidateQueries({ queryKey: keys.inbody(vars.memberId) }),
  });
}

// ── 직원 · 설정 ────────────────────────────────────────────────────────
// enabled — 기본은 켜짐(직원 표·담당 셀렉트·색상 범례처럼 목록 자체가 화면인 곳).
// 끄는 자리는 지금 딱 하나, 셸 헤더다: 계약 v2.2로 /v1/me가 이름을 실어주면서 헤더는 이름
// 하나 때문에 이 목록을 부를 이유가 없어졌다(그게 v2.2의 목적이다). 다만 name은 best-effort라
// 없을 수 있어 조인 폴백 자체는 남기고, **필요할 때만** 켠다.
// enabled=false여도 다른 화면이 이미 받아둔 캐시는 그대로 읽힌다(같은 queryKey) — 폴백이
// 약해지지 않고 요청만 사라진다.
export function useStaff(enabled = true) {
  return useQuery({ queryKey: keys.staff, queryFn: () => api.staff(), enabled });
}

// 트레이너 초대(v1.8, owner 전용) — 방금 초대한 사람이 직원 표에 바로 뜨도록 staff 캐시를
// 무효화한다(담당 트레이너 셀렉트·예약 그리드 색상표도 같은 키를 쓰므로 함께 최신화된다).
// 비밀번호 설정 메일 발송은 화면(Settings.tsx)이 Firebase 클라이언트 SDK로 이어서 처리한다 —
// 서버상태가 아니라 이 훅의 책임이 아니다.
export function useCreateStaff() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: CreateStaffRequest) => api.createStaff(body),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.staff }),
  });
}

export function useSetOffdays() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ uid, offdays }: { uid: string; offdays: string[] }) => api.setOffdays(uid, offdays),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.staff }),
  });
}

// 트레이너 프로필(v1.6) — "통 교체" 시맨틱: 폼 상태 전체를 항상 전송한다. 성공 시 직원 목록을
// 최신화해 표의 아바타·직함 서브텍스트·"프로필 미등록" 뱃지가 바로 갱신되게 한다.
export function useUpdateStaffProfile() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ uid, profile }: { uid: string; profile: StaffProfile }) =>
      api.updateStaffProfile(uid, profile),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.staff }),
  });
}

// 트레이너 사진 업로드(owner 전용) — 이웃 프로필 뮤테이션과 **같은 키 하나**(keys.staff)를 비운다.
// 서버가 photo_url을 프로필에 함께 저장하므로 이 무효화 한 번으로 직원 표의 아바타·"프로필
// 미등록" 뱃지·예약 그리드가 함께 갱신된다(별도 캐시가 없다).
//
// invalidateQueries의 **프로미스를 돌려준다**(useRotateCheckinQr와 같은 근거): 그래야 재조회가
// 끝날 때까지 isPending이 유지돼, 버튼이 "올리는 중…"에서 풀리는 순간의 화면이 이미 새 사진이다.
// 삼키면 pending이 먼저 풀려 옛 아바타가 잠깐 남고, 그 창에서 대표가 같은 사진을 또 올린다.
export function useUploadStaffPhoto() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ uid, body }: { uid: string; body: StaffPhotoUploadRequest }) =>
      api.uploadStaffPhoto(uid, body),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.staff }),
  });
}

// ── 직원 생애주기(v2.0, owner 전용) ────────────────────────────────────

// 정정(PUT /v1/staff/{uid}) — 이름·색·정산·역할. 이름과 색은 직원 표뿐 아니라 스케줄 그리드의
// 블록 색·색상 범례·회원 담당 배지까지 전부 staff 캐시에서 나오므로 그 한 키만 비우면 화면
// 전체가 함께 갱신된다. 정산·역할은 트레이너 비교표(stats.by_trainer)의 행 라벨도 바꾼다.
export function useUpdateStaff() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ uid, patch }: { uid: string; patch: StaffUpdateRequest }) =>
      api.updateStaff(uid, patch),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keys.staff });
      qc.invalidateQueries({ queryKey: ["stats"] });
    },
  });
}

// 담당 일괄 이관 — Member.trainer_id · Pass.trainer_id · Recurring.trainer_id · 미래 confirmed
// Booking(+Slot.teams 사본)을 한 번에 재지정하고 패스마다 원장에 reason="transfer"를 남긴다.
// 그래서 회원·원장·고정 스케줄·슬롯 그리드·예약 목록·정산 귀속(stats)이 **전부** 흔들린다 —
// 하나라도 빠뜨리면 "이관했는데 화면은 그대로"가 되어 대표가 퇴사를 다시 눌렀다가 또 막힌다.
export function useTransferStaff() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ uid, toUid }: { uid: string; toUid: string }) => api.transferStaff(uid, toUid),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["members"] });
      qc.invalidateQueries({ queryKey: ["memberLedger"] });
      qc.invalidateQueries({ queryKey: ["recurrings"] }); // 만료 포함/미포함 두 목록 모두
      qc.invalidateQueries({ queryKey: ["slots"] });
      qc.invalidateQueries({ queryKey: ["bookings"] });
      qc.invalidateQueries({ queryKey: ["stats"] });
      qc.invalidateQueries({ queryKey: keys.staff });
    },
  });
}

// 퇴사·복직 — status가 바뀌면 모든 담당 트레이너 셀렉트(신규 선택은 active만)·필터 칩·색상
// 범례의 구성이 달라진다. 전부 staff 캐시를 읽으므로 그 키 하나로 함께 갱신된다.
// stats도 함께: by_trainer 행의 status 배지와 포함 여부(활동 있는 기간만)가 바뀐다.
export function useDeactivateStaff() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ uid, leftAt }: { uid: string; leftAt?: string }) =>
      api.deactivateStaff(uid, leftAt),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keys.staff });
      qc.invalidateQueries({ queryKey: ["stats"] });
    },
  });
}

export function useReactivateStaff() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (uid: string) => api.reactivateStaff(uid),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keys.staff });
      qc.invalidateQueries({ queryKey: ["stats"] });
    },
  });
}

export function useCenter() {
  return useQuery({ queryKey: keys.center, queryFn: () => api.center() });
}

// 운영 정책 편집(v1.4, owner 전용) — 저장 성공 시 정책 조회 캐시 최신화.
export function useUpdateCenterPolicy() {
  const qc = useQueryClient();
  return useMutation({
    // patch — 바뀐 필드만(서버 머지 시맨틱을 살린다, P14 M5).
    mutationFn: (patch: Partial<CenterPolicy>) => api.updateCenterPolicy(patch),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.center }),
  });
}

// 사업자 정보 편집(v2.13, owner 전용) — 정책과 **같은 keys.center 캐시**를 무효화한다.
// 서버가 어느 덩어리를 저장했든 GET /v1/center 모양 그대로 돌려주기 때문에 캐시 키를 나눌 이유가
// 없고, 나누면 정책 저장 응답에 실려 온 최신 business가 낡은 채로 남는다(같은 문서의 두 조각이
// 서로 다른 시점을 가리키게 된다).
export function useUpdateCenterBusiness() {
  const qc = useQueryClient();
  return useMutation({
    // business — 12칸 전부(서버가 통 교체다, api.updateCenterBusiness 주석). patch가 아니라서
    // 여기서 필드를 골라 담으면 안 된다: 빠뜨린 칸은 머지가 아니라 **빈 값으로 저장**된다.
    mutationFn: (business: CenterBusiness) => api.updateCenterBusiness(business),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.center }),
  });
}

// [P42] 체육시설업 신고 상태 저장(owner 전용) — 정책·사업자 정보와 **같은 keys.center 캐시**를
// 무효화한다(facility가 GET /v1/center 응답의 한 절이라 키를 나누면 같은 문서의 조각들이 서로
// 다른 시점을 가리킨다 — useUpdateCenterBusiness와 같은 근거). 응답이 facility 절뿐이라(Center
// 아님) 캐시를 setQueryData로 직접 갈아끼우지 않고 재조회로 맞춘다.
export function useSaveFacility() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (facility: CenterFacility) => api.saveFacility(facility),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.center }),
  });
}

// ── 데스크 체크인 QR(P49, owner 전용) ──────────────────────────────────
//
// **enabled 게이트를 두지 않는다.** useJoinRequests는 게이트가 필요했다 — 대시보드처럼 두 역할이
// 함께 쓰는 화면에서도 불려서, 트레이너에게 403을 받아놓고 "조회 실패"를 그리게 되기 때문이다.
// 이 훅의 호출부는 딱 하나(CheckinQrCard)고 그 카드는 **owner 게이트 두 겹** 뒤에 있다:
// App.tsx `section === "set" && isOwner && <Settings />` → Settings.tsx `{isOwner && <CheckinQrCard/>}`.
// 트레이너 세션에서는 컴포넌트가 마운트조차 되지 않아 훅이 실행되지 않는다 — 안 쓰이는 인자를
// 열어두면 "게이트가 필요한 훅"으로 오해돼 호출부마다 판단이 갈린다.
export function useCheckinQr() {
  return useQuery({ queryKey: keys.checkinQr, queryFn: () => api.checkinQr() });
}

// 발급/재발급 — 응답이 조회와 **같은 모양**이라 setQueryData로 갈아끼울 수도 있지만, 집안
// 규약대로 무효화만 한다(useUpdateCenterBusiness — 응답 모양이 같아도 캐시는 서버 재조회로
// 맞춘다. 두 갈래로 채우면 어느 쪽이 진짜인지 화면마다 달라진다).
//
// invalidateQueries의 **프로미스를 돌려주는 것이 이 훅의 안전장치**다: react-query v5는 onSuccess가
// 돌려준 프로미스를 기다리는 동안 isPending을 유지한다. 그 사이 캐시에는 아직 **옛 토큰**이 들어
// 있는데, 이 화면은 그 값으로 인쇄 시트를 그린다 — 재조회가 끝나기 전에 pending이 풀리면
// "방금 무효가 된 QR"을 인쇄할 수 있는 창이 열린다(대표는 그걸 데스크에 붙인다). 프로미스를
// 삼키면(`onSuccess: () => { qc.invalidate...() }`) 그 창이 그대로 생긴다.
export function useRotateCheckinQr() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.rotateCheckinQr(),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.checkinQr }),
  });
}

// 가입 요청 폴링 주기. **이 화면에서 유일하게 사람이 기다리는 데이터**라서 하나 예외를 둔다 —
// 회원 앱은 "센터에서 승인하면 연결돼요"라고 안내하고 대기 화면에 머무는데, 대표 쪽은
// staleTime 15s + refetchOnWindowFocus:false라 대시보드를 켜둔 채로는 수동 새로고침 전까지
// 새 요청이 뜨지 않았다(두 화면의 약속이 어긋남).
//
// 60초로 잡은 근거:
//  · 위쪽(주기를 늘리면): 앱에서 기다리는 사람이 있는 흐름이다. 5분이면 "왜 아직도"가 되는
//    구간이라 폴링을 붙인 의미가 사라진다.
//  · 아래쪽(주기를 줄이면): 30초는 요청·Firestore 조회가 정확히 2배인데 사람의 행동은 바뀌지
//    않는다 — 승인은 대표가 직접 누르는 작업이라 30초와 60초 사이에 결정이 달라지지 않는다.
//  · 비용: 대시보드나 설정 탭을 8시간 켜둔 대표 1명당 하루 480회. 요청당 대기 건수(보통 0~2건)만
//    읽는 목록 조회다. 백그라운드 탭에선 멈추므로(refetchIntervalInBackground 기본 false)
//    자리를 비운 시간은 과금되지 않고, 실제로는 이보다 적게 나간다.
const JOIN_REQUESTS_POLL_MS = 60_000;

// owner 전용 API(비-owner는 서버가 403 — service.ListJoinRequests). 설정 화면은 이미 owner
// 게이트 뒤라 인자 없이 부르고, 대시보드처럼 두 역할이 함께 쓰는 화면은 enabled로 조회를 끈다
// — 트레이너에게 403을 받아놓고 "조회 실패"를 보여주지 않기 위해서다.
// **폴링도 같은 게이트를 탄다**: enabled=false면 최초 조회도 주기 조회도 일어나지 않으므로
// 트레이너 화면이 1분마다 403을 받는 일은 없다(owner 전용이라는 성질이 유지된다).
export function useJoinRequests(enabled = true) {
  return useQuery({
    queryKey: keys.joinRequests,
    queryFn: () => api.joinRequests(),
    enabled,
    // 권한·세션 에러(403/401)에서는 폴링을 멈춘다 — 역할이 바뀌었거나 세션이 끝난 상태에서
    // 1분마다 같은 거절을 다시 받아올 이유가 없다. 그 외(네트워크·5xx)는 계속 시도한다:
    // 일시적 실패로 폴링이 영구히 죽으면 화면을 다시 열기 전까지 조용히 멈춘 채로 남는다.
    refetchInterval: (query) => {
      const e = query.state.error;
      if (e instanceof ApiError && (e.status === 401 || e.status === 403)) return false;
      return JOIN_REQUESTS_POLL_MS;
    },
    // 전역 기본(refetchOnWindowFocus:false)을 이 쿼리만 뒤집는다 — 다른 창에서 일하다 돌아온
    // 순간이 대표가 목록을 확인하는 시점이다. 전역 staleTime 15초가 연타 포커스를 흡수한다.
    refetchOnWindowFocus: true,
  });
}

// 재등록/상담 요청(계약 v2.20, P42) — 가입 요청과 같은 폴링·포커스 규약. 단 owner 게이트가
// 없다: 서버가 역할 스코프를 정한다(owner 전체 / trainer 담당만) — enabled로 끌 이유가 없고,
// 트레이너에게도 자기 담당의 손든 회원은 할 일이다.
export function useConsultRequests() {
  return useQuery({
    queryKey: keys.consultRequests,
    queryFn: () => api.consultRequests(),
    refetchInterval: (query) => {
      const e = query.state.error;
      if (e instanceof ApiError && (e.status === 401 || e.status === 403)) return false;
      return JOIN_REQUESTS_POLL_MS;
    },
    refetchOnWindowFocus: true,
  });
}

export function useConsultDone() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.consultRequestDone(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keys.consultRequests });
    },
  });
}

export function useApproveJoin() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (requestId: string) => api.joinApprove(requestId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keys.joinRequests });
      // 승인 시 회원 생성/연결이 일어난다 — 회원 목록도 최신화.
      qc.invalidateQueries({ queryKey: ["members"] });
    },
  });
}
