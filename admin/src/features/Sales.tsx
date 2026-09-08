// 매출·통계 — 목업 s-sales 1:1(대표 전용, App.tsx에서 owner 게이트). 범위는 과제 지시대로
// KPI·월차트(SVG)·트레이너 비교표·환불계산기 4개 핵심. 상품별 매출·진입경로는 계약 Stats에
// 없는 지표라 회원 목록(+임베드 회원권) 데이터를 클라이언트에서 집계한 보너스 카드로 제공한다.
import { useMemo, useState } from "react";
import { Calculator } from "lucide-react";
import {
  Badge,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  ErrorState,
  Input,
  Label,
  ProgressBar,
  Spinner,
  TD,
  TH,
  THead,
  TR,
  Table,
} from "@/components/ui";
import { useCenter, useMembers, useStats } from "@/lib/queries";
import { NO_VALUE, formatCurrency, formatRatio, isStaffActive, ratioState } from "@/lib/format";
import { MAX_PENALTY_PCT, type MonthlyRevenue } from "@/lib/types";

/**
 * `"2026-08"` → `"2026년 8월"`(withYear) · `"8월"`(차트 가로축).
 *
 * 서버가 주는 `YYYY-MM`은 저장용 표기지 사람에게 보여줄 말이 아니다 — "이번 달 매출"이라는
 * 제목 바로 아래 `2026-08`이 놓이면 그게 날짜인지 코드인지부터 읽어야 한다.
 * 모양이 다른 값이 오면 지어내지 않고 원문을 그대로 둔다(무엇을 받았는지 보여야 문의가 된다).
 * format.ts는 이 화면의 소관이 아니라 여기 둔다 — 다른 화면도 쓰게 되면 그때 함께 옮긴다.
 */
function formatMonthLabel(month: string | null | undefined, withYear: boolean): string {
  if (!month) return NO_VALUE;
  const [y, m] = month.split("-");
  const yn = Number(y);
  const mn = Number(m);
  if (!y || !m || !Number.isFinite(yn) || !Number.isFinite(mn)) return month;
  return withYear ? `${yn}년 ${mn}월` : `${mn}월`;
}

export function Sales() {
  const statsQ = useStats("ytd", "center");
  const membersQ = useMembers();
  const stats = statsQ.data;
  // 재등록 인정기간은 정책 실값 — 설정에서 바꾸면 카피도 따라온다(로딩 전엔 시드 기본값 90 폴백).
  const centerQ = useCenter();
  const reregWindowDays = centerQ.data?.policy.rereg_window_days ?? 90;

  const thisMonth = stats && stats.monthly.length > 0 ? stats.monthly[stats.monthly.length - 1] : undefined;

  // KPI 비율 3종의 표시 상태(format.ts ratioState — 값 / 집계 대상 0 / 미상). 큰 숫자와 그 아래
  // 설명문이 **같은 판단 하나**에서 갈라지게 묶어 둔다: 종전엔 숫자는 "—"인데 설명만 "0명"·"없어요"로
  // 단정하는 조합이 나올 수 있었다. stats 미도착이면 위 분기가 이 카드를 아예 그리지 않는다.
  const reregView = ratioState(stats?.rereg_rate, stats?.rereg_d, 0);
  const noshowView = ratioState(stats?.noshow_rate, stats?.noshow_d);
  const hwView = ratioState(stats?.hw_rate, stats?.hw_d);

  const channelBreakdown = useMemo(() => {
    const counts = new Map<string, number>();
    for (const m of membersQ.data ?? []) {
      const key = m.channel || "미지정";
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    const total = [...counts.values()].reduce((a, b) => a + b, 0) || 1;
    return [...counts.entries()]
      .map(([channel, n]) => ({ channel, n, pct: (n / total) * 100 }))
      .sort((a, b) => b.n - a.n);
  }, [membersQ.data]);

  const productBreakdown = useMemo(() => {
    const sums = new Map<string, number>();
    for (const m of membersQ.data ?? []) {
      for (const p of m.passes) {
        // 순액 정합: 환불된 회원권은 제외 — 서버 매출(monthly/ytd) "환불 제외" 규약과 맞춘다.
        if (p.status === "refunded") continue;
        sums.set(p.product, (sums.get(p.product) ?? 0) + p.paid_amount);
      }
    }
    const total = [...sums.values()].reduce((a, b) => a + b, 0) || 1;
    return [...sums.entries()]
      .map(([product, amount]) => ({ product, amount, pct: (amount / total) * 100 }))
      .sort((a, b) => b.amount - a.amount);
  }, [membersQ.data]);

  return (
    <div>
      <h2 className="flex items-center gap-2 text-[16.5px] font-bold">
        매출 · 통계 <Badge tone="brand">대표 전용</Badge>
      </h2>
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        트레이너에게는 이 메뉴가 보이지 않습니다(본인 정산·통계는 대시보드에서 별도 제공).
      </p>

      {statsQ.isLoading ? (
        <Spinner />
      ) : statsQ.isError ? (
        <ErrorState error={statsQ.error} onRetry={() => void statsQ.refetch()} />
      ) : !stats ? (
        <EmptyState>통계 데이터가 없습니다.</EmptyState>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
            <Card>
              <CardContent className="pt-3.5">
                {/* v1.5: monthly/ytd/by_trainer는 환불 거래 제외(순매출) — 라벨로 명시. */}
                <div className="text-[11px] text-muted">연 매출 (순액 · 환불 제외)</div>
                <div className="my-0.5 text-[21px] font-black">{formatCurrency(stats.ytd)}</div>
                {/* 목표 0 = **미설정**이지 "달성률 100%"가 아니다(P14 M4). 종전엔 `target || 1`로
                    0을 1원으로 바꿔 막대가 가득 찼고, ui.tsx의 100 클램프가 그 값을 곱게 다듬어
                    신규 센터는 첫 화면부터 목표를 다 채운 것처럼 보였다(policy.go 기본값이 0).
                    분모 0을 성과로 읽지 않는 규칙은 format.ts ratioState가 이미 세워둔 것이다. */}
                {stats.target > 0 ? (
                  <>
                    <ProgressBar value={(stats.ytd / stats.target) * 100} className="my-1" />
                    <div className="text-[10.5px] text-muted">
                      목표 {formatCurrency(stats.target)} ·{" "}
                      <b className="text-ink">
                        {formatCurrency(Math.max(0, stats.target - stats.ytd))} 남음
                      </b>
                    </div>
                  </>
                ) : (
                  <div className="mt-1.5 text-[10.5px] text-muted">
                    연 매출 목표 미설정 — 달성률을 계산할 기준이 없어요.{" "}
                    <b className="text-ink">설정 · 직원</b>에서 정하면 여기에 진행 막대가 생깁니다.
                  </div>
                )}
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-3.5">
                <div className="text-[11px] text-muted">이번 달 매출 (진행)</div>
                <div className="my-0.5 text-[21px] font-black">{formatCurrency(thisMonth?.amount)}</div>
                <div className="text-[10.5px] text-muted">
                  {formatMonthLabel(thisMonth?.month, true)}
                </div>
              </CardContent>
            </Card>
            {/* v1.5 재정의: 미수금 = 연체(due 경과 미납 회차)만 — 미도래 미납은 서브라인으로 분리.
                환불로 청구 종결(waived)된 회차는 서버 집계에서 이미 제외된다. */}
            <Card>
              <CardContent className="pt-3.5">
                <div className="text-[11px] text-muted">미수금 (연체)</div>
                <div
                  className={`my-0.5 text-[21px] font-black ${stats.unpaid_count > 0 ? "text-danger" : "text-ok"}`}
                >
                  {formatCurrency(stats.unpaid_total)}
                </div>
                <div className="text-[10.5px] text-muted">
                  {stats.unpaid_count > 0 ? (
                    <>
                      연체 <b className="text-warn">{stats.unpaid_count}건</b> — 회원 상세 결제
                      목록에서 납부 처리
                    </>
                  ) : (
                    "연체 0건 — 기한 지난 미납이 없어요"
                  )}
                  <br />
                  미도래 {formatCurrency(stats.upcoming_total)}
                  <span className="opacity-70"> (기한 전 분할 회차 — 연체 아님)</span>
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-3.5">
                <div className="text-[11px] text-muted">재등록률</div>
                {/* 분모 0(만료된 회원이 아직 없음)은 "0%"가 아니라 "—" — 없는 모수를 실패로 읽히게 하지 않는다. */}
                <div className="my-0.5 text-[21px] font-black">{reregView.text}</div>
                <div className="text-[10.5px] text-muted">
                  {reregView.kind === "value"
                    ? `${stats.rereg_n}/${stats.rereg_d}명 · 만료 후 ${reregWindowDays}일 내`
                    : reregView.kind === "none"
                      ? `만료 회원 0명 · 만료 후 ${reregWindowDays}일 내 집계`
                      : `만료 후 ${reregWindowDays}일 내 집계 — ${reregView.note}`}
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-3.5">
                <div className="text-[11px] text-muted">노쇼율 · HW 완료율</div>
                {/* 분모 0(집계 대상 예약·배정이 아직 없음)은 "0%"가 아니라 "—" — 계약 v2.1의
                    noshow_d·hw_d로 "성과 0"과 "모수 없음"을 가른다(재등록률 카드와 같은 규칙).
                    노쇼율 0%는 좋아 보이고 HW 0%는 나빠 보이지만 둘 다 같은 "아직 없음"이다. */}
                <div className="my-0.5 text-[21px] font-black">{noshowView.text}</div>
                <div className="text-[10.5px] text-muted">
                  {/* 노쇼와 HW는 분모가 서로 다르다(예약 수 vs 배정 수) — 한쪽만 비어 있을 수 있어
                      아래 기준 문장에 얹지 않고 그 자리에서 이유를 붙인다. */}
                  HW 완료율 {hwView.text}
                  {hwView.kind !== "value" && ` (${hwView.note})`}
                  <br />
                  {/* 분모 0(서버가 실제로 0을 실어 보냄)과 분모 부재(v2.1 이전 서버라 미상)를
                      가른다 — 후자에서 "예약이 아직 없어요"라고 쓰면 모르는 것을 단정하게 된다. */}
                  {noshowView.kind === "value"
                    ? `완료·노쇼 ${stats.noshow_d}건 기준`
                    : noshowView.kind === "none"
                      ? "완료·노쇼로 마감된 예약 0건"
                      : noshowView.note}
                </div>
              </CardContent>
            </Card>
          </div>

          <Card className="mt-3">
            <CardHeader>
              <CardTitle>월간 매출</CardTitle>
            </CardHeader>
            <CardContent>
              <MonthlyChart monthly={stats.monthly} />
            </CardContent>
          </Card>

          <div className="mt-3 grid gap-3 md:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>상품별 매출</CardTitle>
              </CardHeader>
              <CardContent>
                {/* 회원 목록 로딩 중을 "데이터 없음"으로 위장하지 않는다 — 빈 상태 오판 방지. */}
                {membersQ.isLoading ? (
                  <Spinner />
                ) : membersQ.isError ? (
                  <ErrorState error={membersQ.error} onRetry={() => void membersQ.refetch()} />
                ) : !productBreakdown.length ? (
                  <EmptyState>집계할 회원권 데이터가 없습니다.</EmptyState>
                ) : (
                  productBreakdown.map((row) => (
                    <HBar key={row.product} label={row.product} pct={row.pct} value={formatCurrency(row.amount)} />
                  ))
                )}
                <p className="mt-2 text-[10.5px] text-muted">
                  {/* 서버 Stats에 없는 지표라 화면에서 직접 집계한다 — 산출 근거만 밝히고
                      내부 문서 참조는 남기지 않는다(사용자에게 의미 없는 정보). */}
                  등록된 회원권의 실결제액 기준으로 집계했어요(환불 건 제외).
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardHeader>
                <CardTitle>진입경로</CardTitle>
              </CardHeader>
              <CardContent>
                {membersQ.isLoading ? (
                  <Spinner />
                ) : membersQ.isError ? (
                  <ErrorState error={membersQ.error} onRetry={() => void membersQ.refetch()} />
                ) : !channelBreakdown.length ? (
                  <EmptyState>집계할 회원 데이터가 없습니다.</EmptyState>
                ) : (
                  channelBreakdown.map((row) => (
                    <HBar key={row.channel} label={row.channel} pct={row.pct} value={`${row.n}명`} />
                  ))
                )}
                <p className="mt-2 text-[10.5px] text-muted">
                  계약 등록 시 진입경로가 필수 입력이라 "미지정" 쏠림이 생기지 않는 것이 정상입니다.
                </p>
              </CardContent>
            </Card>
          </div>

          <Card className="mt-3">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                트레이너 비교 <Badge tone="brand">대표 전용</Badge>
              </CardTitle>
            </CardHeader>
            <CardContent>
              {!stats.by_trainer?.length ? (
                <EmptyState>트레이너별 비교 데이터가 없습니다.</EmptyState>
              ) : (
                <Table>
                  <THead>
                    <TR>
                      <TH>트레이너</TH>
                      <TH>정산액</TH>
                      <TH>재등록률</TH>
                      <TH>노쇼율</TH>
                      <TH>HW 완료</TH>
                    </TR>
                  </THead>
                  <tbody>
                    {stats.by_trainer.map((t) => (
                      <TR key={t.uid} className={isStaffActive(t) ? undefined : "opacity-70"}>
                        <TD className="font-bold">
                          {t.name}
                          {/* v2.0: inactive 행은 해당 기간에 활동이 있을 때만 온다 — 왜 퇴사자가
                              표에 남아 있는지를 배지가 그 자리에서 설명한다(정산 이력 보존). */}
                          {!isStaffActive(t) && (
                            <Badge tone="muted" className="ml-1.5">
                              퇴사
                            </Badge>
                          )}
                        </TD>
                        <TD>
                          <b>{formatCurrency(t.revenue)}</b>{" "}
                          <span className="text-muted">({t.sessions}회)</span>
                        </TD>
                        <TD>
                          <b>{formatRatio(t.rereg_rate, t.rereg_d, 0)}</b>{" "}
                          {t.rereg_d > 0 && `(${t.rereg_n}/${t.rereg_d})`}
                        </TD>
                        {/* 계약 v2.1이 by_trainer 행에도 noshow_d·hw_d를 실으면서 닫힌 칸이다
                            (백엔드 domain.TrainerStats — json 키는 top-level Stats와 동일).
                            이번 기간에 수업이 없던 코치는 분모가 0이라 "—" — 종전엔 "노쇼 0.0%"로
                            표의 최우수처럼 보였다. 위 KPI 카드와 같은 ratioState를 탄다. */}
                        <TD>{formatRatio(t.noshow_rate, t.noshow_d)}</TD>
                        <TD>{formatRatio(t.hw_rate, t.hw_d)}</TD>
                      </TR>
                    ))}
                  </tbody>
                </Table>
              )}
              <p className="mt-2 text-[10.5px] text-muted">
                재등록률 = 만료 시점 담당 기준(동일 트레이너 재계약). 트레이너는 본인 수치+센터
                평균만 봅니다 — 비교표는 대표 전용입니다. 이번 기간에 집계 대상이 없는 칸은
                "—"입니다(0%가 아니라 비교 자체가 불가능한 행이라는 뜻).
              </p>
              {/* 두 열이 통째로 "—"가 되면 대표는 고장으로 읽는다 — 그 상태만 골라 한 줄로
                  설명한다(구버전 서버가 분모를 안 싣던 v2.1 이전 조건. v2.1부터는 안 뜬다).
                  종전 문구는 두 가지가 틀렸다: ① "감췄어요"라고 했지만 열은 그대로 있고 값만
                  "—"다(화면과 다른 말) ② 원인이 서버 버전이라 대표가 할 수 있는 일이 없는데
                  마치 조치를 기다리는 것처럼 읽혔다. 지금은 **보이는 것 그대로** 설명하고,
                  대신 "나머지 숫자는 믿어도 된다"는 실제로 쓸모 있는 정보를 준다. */}
              {stats.by_trainer?.some((t) => t.noshow_d === undefined || t.hw_d === undefined) && (
                <p className="mt-1 text-[10.5px] text-warn">
                  이번에는 노쇼율·HW 완료율을 계산할 기준 건수가 함께 오지 않아 두 열을 "—"로 비워
                  뒀어요 — 0%로 채우면 노쇼는 잘한 것처럼, HW는 못한 것처럼 보여서 추측해 넣지
                  않습니다. 정산액·재등록률은 평소대로 보셔도 됩니다.
                </p>
              )}
            </CardContent>
          </Card>
        </>
      )}

      <RefundCalculatorCard />
    </div>
  );
}

function HBar({ label, pct, value }: { label: string; pct: number; value: string }) {
  return (
    <div className="my-1 flex items-center gap-2 text-[11.5px]">
      <span className="w-16 shrink-0 text-muted">{label}</span>
      <ProgressBar value={pct} className="flex-1" />
      <span className="w-16 shrink-0 text-right font-bold">{value}</span>
    </div>
  );
}

function MonthlyChart({ monthly }: { monthly: MonthlyRevenue[] }) {
  if (!monthly.length) return <EmptyState>월별 매출 데이터가 없습니다.</EmptyState>;
  const W = 560;
  const H = 110;
  const padX = 20;
  const padTop = 14;
  const padBottom = 22;
  const max = Math.max(...monthly.map((m) => m.amount), 1);
  const stepX = monthly.length > 1 ? (W - padX * 2) / (monthly.length - 1) : 0;
  const points = monthly.map((m, i) => ({
    x: padX + stepX * i,
    y: padTop + (1 - m.amount / max) * (H - padTop - padBottom),
    m,
  }));
  const polyline = points.map((p) => `${p.x},${p.y}`).join(" ");

  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`}>
      <text x={0} y={12} fontSize={9} fill="#8b8fa3">
        원
      </text>
      <polyline points={polyline} fill="none" stroke="#7fa0c4" strokeWidth={2.5} />
      {points.map((p, i) => (
        <circle key={i} cx={p.x} cy={p.y} r={i === points.length - 1 ? 3.5 : 3} fill="#7fa0c4" />
      ))}
      {points.map((p, i) => (
        <text key={i} x={p.x} y={H - 4} fontSize={9} fill="#8b8fa3" textAnchor="middle">
          {formatMonthLabel(p.m.month, false)}
        </text>
      ))}
    </svg>
  );
}

// 환불 계산기(정책 예시) — API계약 골든값(1,000,000·20회·7회사용·10% → 환불 550,000)과 동일한
// 공식을 클라이언트에서 재현한 "정책 계산기"다. 실제 회원권 환불 처리는 회원 상세의
// POST /v1/passes/{id}/refund-quote(실 API 호출, Members.tsx)를 사용한다.
//
// **상한을 실제로 건다**(P14 C1): 종전엔 입력을 100%까지 받아 그대로 곱했고, 그 옆에서 같은
// 값을 "× N%(상한)"이라 불렀다 — 30%를 넣으면 계산기는 300,000원, 서버는 100,000원을 냈다.
// 계산기가 서버와 다른 답을 내면 그건 계산기가 아니라 오답표다.
function RefundCalculatorCard() {
  const [paid, setPaid] = useState(1_000_000);
  const [total, setTotal] = useState(20);
  const [used, setUsed] = useState(7);
  const [ratePct, setRatePct] = useState(MAX_PENALTY_PCT);

  const perSession = total > 0 ? paid / total : 0;
  const usage = perSession * used;
  // 서버 domain.RefundQuote와 같은 캡. 입력도 상한까지만 받으므로 정상 경로에선 항등이지만,
  // 두 곳 중 하나만 두면 다시 어긋난다 — 공식이 곧 상한을 포함해야 한다.
  const effectiveRate = Math.min(ratePct, MAX_PENALTY_PCT) / 100;
  const penalty = paid * effectiveRate;
  const refund = Math.max(0, paid - usage - penalty);

  return (
    <Card className="mt-3">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Calculator className="h-4 w-4 text-brand" /> 환불 계산기 (정책 예시)
        </CardTitle>
        <Badge tone="ok">실제 환불과 같은 공식</Badge>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
          <div>
            <Label>계약금액</Label>
            <Input type="number" value={paid} onChange={(e) => setPaid(Number(e.target.value))} />
          </div>
          <div>
            <Label>총 회차</Label>
            <Input type="number" value={total} onChange={(e) => setTotal(Number(e.target.value))} />
          </div>
          <div>
            <Label>사용 회차</Label>
            <Input type="number" value={used} onChange={(e) => setUsed(Number(e.target.value))} />
          </div>
          <div>
            <Label>위약금율(%, 상한 {MAX_PENALTY_PCT}%)</Label>
            <Input
              type="number"
              min={0}
              max={MAX_PENALTY_PCT}
              step={0.1}
              value={ratePct}
              // 상한 밖(집행되지 않는 요율)과 음수(환불 과대)를 입력 단계에서 클램프.
              onChange={(e) =>
                setRatePct(Math.min(MAX_PENALTY_PCT, Math.max(0, Number(e.target.value) || 0)))
              }
            />
          </div>
        </div>
        <div className="mt-3 rounded-[10px] bg-panel-2 p-3 text-[12.5px] leading-[1.9]">
          회당 단가 = 계약금액 ÷ 총 회차 = {formatCurrency(perSession)} → × {used}회 ={" "}
          <b>{formatCurrency(usage)}</b> 공제
          <br />
          위약금 = 계약금액 {formatCurrency(paid)} × {ratePct}% = <b>{formatCurrency(penalty)}</b>
          <br />
          <span className="text-[14px]">
            환불액 = <b className="text-brand">{formatCurrency(refund)}</b>
          </span>
        </div>
        <p className="mt-2 text-[10.5px] text-muted">
          {/* 내부 티켓 표기(P5 = 정가 공제 금지)와 구현 용어(백엔드 검증·서버)는 코드 주석에만
              남긴다 — 대표에게 필요한 것은 "이 카드는 예시고, 진짜 계산은 어디서 하는지"다. */}
          위약금율은 {MAX_PENALTY_PCT}%가 상한이에요 — 설정 화면에서도 그 위로는 저장되지 않고,
          계약서에 인쇄되는 값과 실제 공제액이 같습니다. 정가로 공제하는 선택지는 없습니다 —
          법원·소비자원 모두 <b>할인 후 실제 거래가</b>를 기준으로 봅니다. 여기는 정책을 확인해
          보는 계산기예요. 특정 회원의 실제 환불은 <b>회원 관리</b>에서 그 회원권을 열어
          처리하세요 — 그때는 그 회원의 실제 결제·사용 기록으로 다시 계산되고, 그 값이 정산
          기준이 됩니다.
          <br />
          <b>분할 납부 중 해지</b>라면 여기 숫자와 달라집니다 — 실제 환불은 <b>지금까지 실제로
          받은 금액</b>(계약금액이 상한)에서 시작하고, 회당 단가와 위약금만 계약금액 기준으로
          계산해요.
        </p>
      </CardContent>
    </Card>
  );
}
