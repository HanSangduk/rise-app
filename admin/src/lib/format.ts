// 화면 전역에서 쓰는 표기 유틸 — 통화·날짜·퍼센트·slotKey 변환.
import { WEEKDAY_LABEL, type Weekday } from "./types";

const KRW = new Intl.NumberFormat("ko-KR", { style: "currency", currency: "KRW", maximumFractionDigits: 0 });

export function formatCurrency(n: number | null | undefined): string {
  return KRW.format(n ?? 0);
}

// 값을 모르는 자리의 표기. "아직 값이 없다"와 "값이 0이다"는 화면에서 정반대 뜻이라 한 글자로
// 갈라둔다 — 0%는 성과 실패, "—"는 아직 판단할 근거가 없음.
export const NO_VALUE = "—";

// v1.1 정합 패치로 계약 확정: rereg_rate·noshow_rate·hw_rate·payout(rate) 등 비율 필드는
// 0~1 소수로 온다. 표시 시 *100.
//
// **값이 없으면(null·undefined) 0%가 아니라 "—"다.** 종전엔 `n ?? 0`으로 로딩 중·조회 실패를
// "0.0%"로 단정해, 아직 아무것도 모르는 화면이 "성과 0"을 확언하고 있었다. 숫자 0은 그대로
// "0.0%"로 나간다 — 위약금율 0%(회원이 동의한 값)·요율 0% 같은 **의미 있는 0**은 손대지 않는다.
export function formatPercent(n: number | null | undefined, digits = 1): string {
  if (n === null || n === undefined) return NO_VALUE;
  return `${(n * 100).toFixed(digits)}%`;
}

// ── 분모 있는 비율의 3상태(계약 v2.1) ──────────────────────────────────
// 화면에 뜨는 "0.0%"는 세 가지 서로 다른 사정을 덮고 있었다. 백엔드 domain.Rate()가 분모 0에
// 0을 돌려주므로 비율값만으로는 셋을 가를 수 없다 — 분모를 함께 받아 여기 한 곳에서 가른다.
//
//   value   분모 > 0        → **진짜 값**. 0.0%도 그대로 보여준다(집계 대상은 있는데 성과가 0).
//   none    분모 === 0      → 집계 대상 없음. 서버가 실제로 0을 실어 보낸 **사실**이다
//                             (계약 v2.1이 noshow_d·hw_d에 omitempty를 금지한 이유가 이것).
//   unknown 분모 필드 부재  → **미상**. v2.1 이전 서버라 분모를 모른다.
//
// none과 unknown을 `!denominator` 하나로 뭉치면 unknown 자리에서 "집계 대상이 없어요"라고
// **모르는 것을 단정**하게 된다(계약 v2.1 클라이언트 규약이 명시적으로 금지한 자리). 종전엔
// 같은 응답을 두고 Sales는 "—", 대시보드 비교표는 값 그대로, 대시보드 HW 카드는 "배정이
// 없어요"로 서로 다른 답을 내놨다 — 세 자리 모두 이 함수 하나만 보게 통일한다.
//
// 문구 원칙: none에서는 서버가 준 수치를 **사실 그대로**("집계 대상 0건") 쓰고, 원인을 지목하는
// 단정("배정이 없어요")은 쓰지 않는다. unknown에서는 값도 감추고 "아직 못 받았다"고만 말한다.
export type RatioKind = "value" | "none" | "unknown";

export interface RatioState {
  kind: RatioKind;
  /** 값 자리에 그대로 넣는 문자열. value일 때만 퍼센트, 나머지는 "—". */
  text: string;
  /** 게이지·비교 화살표처럼 수치가 필요한 자리용. value일 때만 채워진다. */
  rate?: number;
  /** "—" 옆에 붙일 보조 문구. 화면 도메인 명사가 필요하면 호출부가 kind로 갈라 쓴다. */
  note?: string;
}

export function ratioState(
  n: number | null | undefined,
  denominator: number | null | undefined,
  digits = 1,
): RatioState {
  if (denominator === null || denominator === undefined)
    return { kind: "unknown", text: NO_VALUE, note: "집계 기준을 아직 받지 못했어요" };
  if (denominator === 0) return { kind: "none", text: NO_VALUE, note: "집계 대상 0건" };
  // 분모는 있는데 비율이 없는 응답(부분 필드 누락)도 미상이다 — 0%로 단정하지 않는다.
  if (n === null || n === undefined)
    return { kind: "unknown", text: NO_VALUE, note: "값을 아직 받지 못했어요" };
  return { kind: "value", text: formatPercent(n, digits), rate: n };
}

// 문자열만 필요한 자리(KPI 큰 숫자·표 셀)용 얇은 래퍼 — 정책은 위 ratioState 한 곳에만 있다.
export function formatRatio(
  n: number | null | undefined,
  denominator: number | null | undefined,
  digits = 1,
): string {
  return ratioState(n, denominator, digits).text;
}

// ── 직원 생애주기 표기(v2.0) ────────────────────────────────────────────
// 서버 규약과 동형(domain.Staff.IsActive): **"inactive"만이 명시적 퇴사**이고 필드 부재·빈 값은
// 재직으로 읽는다. 반대로 짰다면 status를 아직 안 내려주는 응답 하나에 전 직원이 퇴사자로 뒤집힌다.
export function isStaffActive(s: { status?: string | null } | null | undefined): boolean {
  return s?.status !== "inactive";
}

// 이름 해석은 퇴사 뒤에도 계속한다 — 회원 목록·스케줄 그리드·색상 범례가 이름을 잃으면 그 자리는
// 원시 uid나 "미배정"이라는 거짓말로 붕괴한다(계약 v2.0). 대신 "(퇴사)"를 같은 자리에 붙여
// "지금 새로 배정할 수 있는 사람"과 구분한다.
export function staffLabel(s: { name: string; status?: string | null }): string {
  return isStaffActive(s) ? s.name : `${s.name} (퇴사)`;
}

// ── 표시 이름 폴백 사슬(v2.2) ───────────────────────────────────────────
// 후보를 **순서대로** 보고 내용이 있는 첫 값을 고른다. 없으면 undefined.
//
// `a ?? b ?? c`로 잇지 않는 이유: `??`는 빈 문자열을 값으로 통과시켜 뒤 후보를 가로막는다.
// /v1/me의 name은 omitempty라 보통은 필드째 빠지지만(그러면 `??`도 안전하다), **이름이
// 비었을 때 헤더가 빈칸으로 뜰지 여부를 서버 태그 하나에 걸어두지 않는다** — name은 계약상
// best-effort라 "없음"이 정상 경로다. 사슬의 어느 칸이 비어 와도 다음 칸으로 내려간다.
export function firstNonEmpty(...candidates: (string | null | undefined)[]): string | undefined {
  return candidates.find((c): c is string => typeof c === "string" && c.trim() !== "");
}

const DOW = ["일", "월", "화", "수", "목", "금", "토"];

export function formatDow(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  if (Number.isNaN(d.getTime())) return "";
  return DOW[d.getDay()];
}

export function formatDateWithDow(dateStr: string): string {
  return `${dateStr} (${formatDow(dateStr)})`;
}

export function formatMonthDay(dateStr: string): string {
  const [, m, d] = dateStr.split("-");
  if (!m || !d) return dateStr;
  return `${Number(m)}/${Number(d)}`;
}

// D-day: 미래면 "D-n", 과거면 "n일 경과", 오늘이면 "D-day".
export function daysUntil(dateStr: string): number {
  const target = new Date(dateStr + "T00:00:00").getTime();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((target - today.getTime()) / 86_400_000);
}

export function daysSince(dateStr: string): number {
  return -daysUntil(dateStr);
}

// slotKey = "20260814-20"(YYYYMMDD-HH). API계약_v1.md 명시 포맷.
export function buildSlotKey(dateStr: string, hour: number): string {
  return `${dateStr.replaceAll("-", "")}-${String(hour).padStart(2, "0")}`;
}

export function slotKeyToHour(slotKey: string): number {
  const part = slotKey.split("-")[1];
  return part ? Number(part) : 0;
}

export function slotKeyToDate(slotKey: string): string {
  const ymd = slotKey.split("-")[0] ?? "";
  if (ymd.length !== 8) return "";
  return `${ymd.slice(0, 4)}-${ymd.slice(4, 6)}-${ymd.slice(6, 8)}`;
}

// "20260825-20" → "8/25 (월) 20:00". 퇴사 blockers·이관 충돌이 예약을 가리킬 때, 사람이
// 달력을 열지 않고도 어느 수업인지 알아볼 수 있어야 한다.
export function formatSlotKey(slotKey: string): string {
  const date = slotKeyToDate(slotKey);
  if (!date) return slotKey;
  return `${formatMonthDay(date)} (${formatDow(date)}) ${slotKeyToHour(slotKey)}:00`;
}

// slotKey → 그 수업의 시작 시각(로컬 = 센터 시간대 KST). 파싱 불가면 null.
// 컷오프처럼 "지금부터 몇 시간 뒤"와 비교해야 하는 판정에 쓴다 — 날짜 문자열 비교로는
// 시(hour) 경계를 가를 수 없다.
export function slotKeyStart(slotKey: string): Date | null {
  const date = slotKeyToDate(slotKey);
  if (!date) return null;
  const d = new Date(`${date}T${String(slotKeyToHour(slotKey)).padStart(2, "0")}:00:00`);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function weekdayLabel(w: Weekday): string {
  return WEEKDAY_LABEL[w];
}

// JS Date.getDay()(0=일) → 계약 Weekday 코드로 변환.
const JS_DAY_TO_WEEKDAY: Weekday[] = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
export function dateToWeekday(dateStr: string): Weekday {
  const d = new Date(dateStr + "T00:00:00");
  return JS_DAY_TO_WEEKDAY[d.getDay()];
}

export function todayStr(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function addDays(dateStr: string, delta: number): string {
  const d = new Date(dateStr + "T00:00:00");
  d.setDate(d.getDate() + delta);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}
