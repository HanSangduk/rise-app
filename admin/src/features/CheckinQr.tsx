// 데스크 체크인 QR(P11 → P49) — 설정·직원 화면의 한 섹션. 대표 전용.
//
// 토큰은 **서버가 만들고 서버가 보관한다**(GET /v1/center/checkin-qr · POST …/rotate).
// 이 화면이 하는 일은 두 가지뿐이다: 발급 버튼을 누르는 것, 받은 문자열을 QR로 그려 A4 한 장으로
// 인쇄하는 것.
//
// 종전엔 대표가 서버 배포 설정에 박힌 값을 손으로 받아 적었다. 서버가 그 값을 돌려주지 않으니
// 값을 아는 사람은 개발자뿐이었고, 실사용자인 센터 대표는 **이 화면을 혼자서 끝낼 수 없었다**.
// 붙여넣기 사고 검사·지문 대조·셸 명령 안내는 전부 "사람이 비밀을 손으로 옮긴다"는 전제에서만
// 존재하던 장치라, 전제가 사라진 지금 함께 지웠다(P49).
//
// 토큰 문자열은 화면 어디에도 **글자로 띄우지 않는다** — 종이 위의 QR이 유일한 표현이다.
// "지금 데스크에 붙어 있는 종이가 최신인가"는 토큰 조각이 아니라 **발급 일시**로 가른다
// (아래 formatIssuedAt 주석 — 화면과 인쇄물이 같은 문자열을 쓴다).
//
// 앱이 스캔한 문자열은 가공 없이 qr_token으로 실려 간다. 따라서 QR에는 URL도 JSON도 아닌
// **토큰 원문 하나만** 인코딩한다(접두사를 붙이면 서버 비교에서 그대로 틀린다).
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { QRCodeSVG } from "qrcode.react";
import { Printer, QrCode, RefreshCw, TriangleAlert } from "lucide-react";
import { BrandMark } from "@/components/BrandMark";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  ErrorState,
  Spinner,
} from "@/components/ui";
import { isRouteNotFound } from "@/lib/api";
import { todayStr } from "@/lib/format";
import { useCheckinQr, useRotateCheckinQr } from "@/lib/queries";

// 오류정정 Q(25%). 근거: 이 QR의 최종 형태는 **데스크에 붙는 인쇄물**이라 지문·긁힘·조명 반사로
// 일부 모듈이 상시 훼손된다(화면에 띄우는 QR과 다른 조건). Q는 M(15%)보다 모듈이 늘지만,
// 아래 80mm 인쇄에서는 늘어난 뒤에도 모듈 한 변이 1mm를 크게 웃돌아(→ PRINT_QR_MM 주석)
// 밀도 비용이 실질적으로 0이다. 값이 공짜면 견고한 쪽을 고른다.
// (qrcode.react의 boostLevel 기본값 true라, 버전이 안 늘어나면 H로 자동 승격되기도 한다.)
const QR_LEVEL = "Q" as const;

// 인쇄 크기 80mm. 근거 두 가지(실측은 아래 숫자 그대로 headless Chrome PDF로 확인했다):
//  ① 모듈 크기 — 폰 카메라가 안정적으로 읽으려면 모듈 한 변 0.5mm 이상이 실무 하한이다.
//     짧은 토큰(17바이트)은 레벨 Q에서 버전 2(25모듈) + 규격 여백 4모듈×2 = 33칸 →
//     80/33 ≈ 2.4mm/모듈. 토큰이 64자로 늘어도 49칸 → 1.6mm/모듈이라 하한의 3배다.
//     즉 **서버가 어떤 길이로 발급하든** 이 크기는 안 무너진다(A4 한 장도 그대로 유지된다).
//  ② 스캔 거리 — QR 업계 통용 경험칙은 "인식 거리 ≈ 코드 한 변 × 10". 80mm면 약 80cm까지,
//     데스크에서 팔을 뻗어 대는 30~50cm를 충분히 덮는다.
const PRINT_QR_MM = 80;

// 화면 미리보기. 인쇄 전 눈으로 확인하는 용도라 크게 둘 이유가 없다.
const PREVIEW_PX = 188;

// 배포 시차 안내 — 어드민이 서버보다 먼저 올라간 창(계약 v2.13·P42가 겪은 그 창).
// 이 화면만 조용히 접히면 되고, 데스크에 이미 붙어 있는 종이는 **그대로 동작한다**
// (구서버는 종전 방식으로 토큰을 검사한다) — 그 사실을 함께 말해야 대표가 종이를 떼지 않는다.
const NOT_DEPLOYED_MSG =
  "이 기능이 아직 서버에 올라가지 않았어요 — 서버가 업데이트되면 발급 버튼이 나타납니다. 그동안 데스크에 붙어 있는 QR은 그대로 동작하니 떼지 마세요.";

// "이 배포에는 그 주소가 없다" — 판정은 api.ts isRouteNotFound 한 곳이다(라우터 404 `code`).
// 이 화면은 미발급이 200 {issued:false}로 와서 404를 "데이터 없음"으로 읽을 여지가 원래 없었지만
// (P56이 "유일하게 옳은 적용"으로 판정한 자리), 근거를 status에서 code로 옮겨 두면 다른 화면과
// 같은 규약이 되고 전달 경로가 삼킨 404(비JSON)는 TRANSPORT_MSG로 제 갈 길을 간다.
function isNotDeployed(e: unknown): boolean {
  return isRouteNotFound(e);
}

export function CheckinQrCard() {
  const qrQ = useCheckinQr();
  const rotate = useRotateCheckinQr();
  // 2단 확인(집안 관례 — Members.tsx payConfirm·환불 confirming과 같은 모양).
  const [confirming, setConfirming] = useState(false);
  // 발급 직후 "다음에 할 일"을 말해주는 자리. 첫 발급과 교체는 해야 할 일이 다르다
  // (붙이기 vs 갈아 끼우기) — 같은 문구로 뭉치면 교체 때 종이를 안 바꾼다.
  const [notice, setNotice] = useState<"issued" | "rotated" | null>(null);

  const data = qrQ.data;
  const token = data?.token ?? "";
  // issued 플래그와 실제 문자열을 함께 본다. 서버가 issued:true인데 token:""을 주는 상태는
  // 계약 위반이지만, 그때 화면이 할 수 있는 유일하게 쓸모 있는 일이 "발급 버튼 보여주기"다
  // (재발급하면 정상 토큰이 생긴다) — 빈 QR을 그리거나 크래시하지 않는다.
  const issued = !!data?.issued && token !== "";
  const issuedLabel = formatIssuedAt(data?.issued_at ?? null);

  return (
    <Card className="md:col-span-2">
      <CardHeader>
        <CardTitle>
          <QrCode className="mr-1.5 -mt-0.5 inline h-4 w-4" />
          데스크 체크인 QR
        </CardTitle>
        {data && (issued ? <Badge tone="ok">발급됨</Badge> : <Badge tone="warn">미발급</Badge>)}
      </CardHeader>
      <CardContent>
        {qrQ.isLoading ? (
          <Spinner />
        ) : qrQ.isError ? (
          isNotDeployed(qrQ.error) ? (
            <div className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2.5 text-[11.5px] leading-[1.8] text-warn">
              <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
              {NOT_DEPLOYED_MSG}
            </div>
          ) : (
            <ErrorState error={qrQ.error} onRetry={() => void qrQ.refetch()} />
          )
        ) : !data ? (
          <EmptyState>체크인 QR 정보를 불러오지 못했습니다.</EmptyState>
        ) : !issued ? (
          /* ── 상태 1: 아직 발급 전 — 할 일은 버튼 하나다 ── */
          <div>
            <p className="text-[12px] leading-[1.9]">
              데스크에 붙여두면 회원이 앱으로 스캔해 <b>스스로 출석을 남깁니다</b>. 발급을 누르면
              QR이 만들어지고, A4 안내문 한 장으로 인쇄할 수 있어요.
            </p>
            <div className="mt-3">
              <Button
                disabled={rotate.isPending}
                onClick={() => rotate.mutate(undefined, { onSuccess: () => setNotice("issued") })}
              >
                <QrCode className="h-4 w-4" />
                {rotate.isPending ? "발급 중…" : "체크인 QR 발급"}
              </Button>
            </div>
            {rotate.isError && (
              <p className="mt-2 text-[11px] text-danger">
                {isNotDeployed(rotate.error) ? NOT_DEPLOYED_MSG : rotate.error.message}
              </p>
            )}
            <ul className="mt-3 space-y-0.5 rounded-[10px] bg-panel-2 px-3 py-2.5 text-[11px] leading-[1.9] text-muted">
              <li>
                · <b className="text-ink">개인정보는 담기지 않습니다</b> — 이름도 전화번호도 QR에
                들어가지 않아요.
              </li>
              <li>
                · <b className="text-ink">이 센터 전용</b> QR입니다 — 다른 센터에서는 통하지
                않습니다.
              </li>
            </ul>
          </div>
        ) : (
          /* ── 상태 2: 발급됨 — QR · 발급일 · 인쇄 · 새로 발급 ── */
          <div>
            <p className="text-[12px] leading-[1.9]">
              데스크에 붙여두면 회원이 앱으로 스캔해 <b>스스로 출석을 남깁니다</b>.
            </p>

            <div className="mt-3 grid gap-4 lg:grid-cols-[auto_minmax(0,1fr)]">
              {/* 왼쪽: 미리보기 */}
              <div className="flex flex-col items-center gap-2 lg:w-[248px]">
                <div className="flex h-[212px] w-[212px] items-center justify-center rounded-[13px] border border-line bg-white">
                  {/* 항상 흰 바탕 · 검은 모듈. QR 규격은 "밝은 배경 위 어두운 모듈"이고, 반전은
                      스캐너마다 되기도 안 되기도 한다 — 다크 테마를 QR 안까지 끌고 오지 않는다. */}
                  <QRCodeSVG
                    value={token}
                    size={PREVIEW_PX}
                    level={QR_LEVEL}
                    marginSize={4}
                    bgColor="#ffffff"
                    fgColor="#000000"
                    title="데스크 체크인 QR 미리보기"
                  />
                </div>
                <p className="text-center text-[10.5px] leading-[1.7] text-muted">
                  오류정정 {QR_LEVEL}(25%) · 인쇄 {PRINT_QR_MM}mm
                  <br />
                  데스크 거리(30~50cm)에서 여유 있게 읽히는 크기예요.
                </p>
              </div>

              {/* 오른쪽: 발급일 · 조작 */}
              <div className="min-w-0">
                <div className="rounded-[10px] border border-line bg-panel-2 px-3 py-2.5">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-[11.5px] font-extrabold">발급일</span>
                    <span className="font-mono text-[13px] font-extrabold text-brand">
                      {issuedLabel ?? "일시 미상"}
                    </span>
                  </div>
                  {/* 인쇄물 아래쪽에 같은 문자열이 찍힌다(PrintSheet .qrp-foot) — 그래서 이
                      한 줄이 "붙어 있는 종이가 최신인지"를 판정하는 유일한 수단이 된다. */}
                  <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
                    데스크에 붙어 있는 종이 맨 아래에도 같은 날짜·시각이 작게 적혀 있어요.{" "}
                    <b className="text-ink">두 값이 다르면 그 종이는 옛날 QR</b>이라 스캔해도
                    체크인이 되지 않습니다.
                  </p>
                </div>

                {notice === "issued" && (
                  <p className="mt-2 rounded-[10px] border border-ok/40 bg-ok/10 px-3 py-2 text-[11px] leading-[1.8] text-ok">
                    발급됐어요 — <b>A4 안내문 인쇄</b>를 눌러 한 장 뽑아 데스크에 붙여주세요.
                  </p>
                )}
                {notice === "rotated" && (
                  <p className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
                    <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />새 QR로 바뀌었어요
                    — 지금 데스크에 붙어 있는 종이는 <b>무효</b>입니다. 새로 인쇄해 갈아 끼워주세요.
                  </p>
                )}

                <div className="mt-2.5 flex flex-wrap gap-2">
                  <Button disabled={rotate.isPending} onClick={() => window.print()}>
                    <Printer className="h-4 w-4" /> A4 안내문 인쇄
                  </Button>
                  {!confirming && (
                    <Button
                      variant="outline"
                      disabled={rotate.isPending}
                      onClick={() => setConfirming(true)}
                    >
                      <RefreshCw className="h-3.5 w-3.5" /> 새로 발급
                    </Button>
                  )}
                </div>

                {/* 2단 확인 — 되돌리는 동사가 없는 조작의 집안 관례(Members.tsx 납부·환불).
                    문구는 **무엇이 남는지**가 아니라 무엇이 죽는지를 적는다: 이 버튼의 실제
                    결과는 "새 QR이 생긴다"가 아니라 "붙어 있는 종이가 그 순간 죽는다"이다. */}
                {confirming && (
                  <div className="mt-2 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
                    <p className="text-[11.5px] leading-relaxed text-danger">
                      새로 발급하면 <b>지금 데스크에 붙어 있는 종이는 그 즉시 무효</b>가 됩니다 —
                      회원이 스캔해도 체크인이 되지 않고, 되돌릴 수 없어요.{" "}
                      <b>새로 인쇄해 갈아 끼울 수 있을 때만</b> 진행하세요.
                    </p>
                    <div className="mt-2 flex gap-2">
                      <Button
                        size="sm"
                        variant="danger"
                        disabled={rotate.isPending}
                        onClick={() =>
                          rotate.mutate(undefined, {
                            onSuccess: () => {
                              setConfirming(false);
                              setNotice("rotated");
                            },
                          })
                        }
                      >
                        {rotate.isPending ? "발급 중…" : "새로 발급 확정"}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={rotate.isPending}
                        onClick={() => setConfirming(false)}
                      >
                        취소
                      </Button>
                    </div>
                  </div>
                )}
                {rotate.isError && (
                  <p className="mt-2 text-[11px] text-danger">
                    {isNotDeployed(rotate.error) ? NOT_DEPLOYED_MSG : rotate.error.message}
                  </p>
                )}

                <p className="mt-2.5 text-[10.5px] leading-[1.8] text-muted">
                  사이드바·헤더는 인쇄되지 않습니다. 이 화면에서는 브라우저 인쇄(⌘/Ctrl+P)도 같은
                  안내문 한 장으로 나옵니다.
                </p>
              </div>
            </div>

            {/* ── 동작 규칙(화면·인쇄물 공통 내용) ── */}
            <div className="mt-3 rounded-[10px] bg-panel-2 px-3 py-2.5 text-[11px] leading-[1.9]">
              <div className="mb-1 text-[11.5px] font-extrabold">이 QR이 실제로 하는 일</div>
              <ul className="space-y-0.5 text-muted">
                <li>
                  · 회원이 <b className="text-ink">라이즈 앱 안에서</b> 스캔합니다. 폰 기본 카메라로
                  찍으면 아무 일도 일어나지 않아요 — 담긴 값이 주소가 아니라 토큰 문자열이라 열 곳이
                  없습니다.
                </li>
                <li>
                  · 회원 앱에서의 자리는 <b className="text-ink">홈 "다음 예약" 카드</b>의{" "}
                  <b className="text-ink">셀프 체크인 (데스크 QR 스캔)</b> 버튼입니다 — 데스크에서
                  안내할 때 이 이름으로 말해주세요. <b className="text-ink">다음 예약이 없으면 버튼
                  자체가 보이지 않습니다.</b>
                </li>
                <li>
                  · 예약 <b className="text-ink">시작 시각 ±30분</b> 안에서만 성공합니다(20:00 수업 →
                  19:30~20:30). 그 밖에서는 버튼이 <b className="text-ink">비활성</b>이라 눌리지도
                  않아요.
                </li>
                <li>
                  · 회원이 예약을 고를 필요는 없습니다 — 서버가 그 시간창에 걸친{" "}
                  <b className="text-ink">본인의 확정(confirmed) 예약</b>을 스스로 찾습니다.
                </li>
                <li>
                  · 취소·완료·노쇼 예약은 대상이 아니고, 시간창을 벗어나면 실패합니다. 그럴 땐 대시보드
                  "오늘 수업" 표의 <b className="text-ink">체크인</b> 버튼으로 직원이 대신 처리하세요.
                </li>
                <li>
                  · 체크인은 <b className="text-ink">출석 기록 + 마지막 방문일</b>만 남깁니다(세션 차감은
                  수업 완료 처리 때).
                </li>
                <li>
                  · <b className="text-ink">새로 발급하면 이미 붙여둔 QR은 그 즉시 무효</b>가 됩니다.
                  새로 인쇄해 갈아 끼우세요.
                </li>
              </ul>
            </div>
          </div>
        )}
      </CardContent>

      {/* 인쇄 시트는 화면에서 늘 숨어 있고(#checkin-qr-print { display:none }) 인쇄할 때만 뜬다.
          발급된 토큰이 있을 때만 마운트한다 — 다른 화면에서 ⌘P를 눌렀는데 빈 종이가 나오지 않게.
          재발급이 도는 동안(rotate.isPending)에도 내린다: 그 구간의 캐시에는 아직 **방금 무효가 된
          옛 토큰**이 들어 있어, 시트를 띄워두면 ⌘P 한 번으로 죽은 QR이 종이로 나간다.
          (useRotateCheckinQr이 재조회까지 pending을 끌고 가므로 이 한 조건으로 창 전체가 닫힌다.) */}
      {issued && !rotate.isPending && <PrintSheet token={token} issuedLabel={issuedLabel} />}
    </Card>
  );
}

// ── 인쇄 시트(A4 1장) ──────────────────────────────────────────────────
//
// document.body로 포털한다. 어드민 셸(#root) 안에 두고 "나머지를 전부 숨기는" CSS를 쓰면
// 숨긴 요소가 차지한 높이 때문에 빈 페이지가 따라 나온다 — 셸과 시트를 body의 형제로 갈라두면
// 인쇄 시 #root 하나만 display:none 하면 끝이다(index.css 하단 참고).
//
// 인쇄물 **본문은 회원이 읽는 글**이다 — 운영자용 용어(토큰·confirmed)를 쓰지 않는다.
// 토큰 평문도 싣지 않는다: QR이 이미 그 값을 나르고, 종이에 글자로 적으면 지나가는 사람이
// 손으로 베껴 갈 수 있다. 대신 맨 아래 8pt 한 줄에 **발급 일시**만 남긴다 — 여기만은 회원이
// 아니라 대표가 읽는 자리다(재발급한 뒤 데스크에 붙어 있는 종이가 구버전인지 가르는 표식이고,
// 화면 "발급일" 칸과 **같은 문자열**이라 눈으로 바로 맞춰진다).
function PrintSheet({ token, issuedLabel }: { token: string; issuedLabel: string | null }) {
  useEffect(() => {
    document.body.classList.add("has-qr-print");
    return () => document.body.classList.remove("has-qr-print");
  }, []);

  return createPortal(
    <div id="checkin-qr-print">
      <div className="qrp-sheet">
        {/* 브랜드 헤더(P19) — R 마크 + 영문 워드마크. 간판·앱과 같은 얼굴을 종이에도 준다.
            마크는 brand 톤(네이비) — 종이는 흰 바탕이라 원색 그대로가 규격이다.
            치수는 index.css .qrp-brand가 mm로 지정(size prop은 viewBox용 명목값).
            이 헤더를 얹고도 A4 1장인지는 headless Chrome PDF로 재실측했다(P19 —
            padding-top 12mm→7mm 보정으로 유지, index.css .qrp-sheet 주석 참고). */}
        <div className="qrp-brand">
          <BrandMark size={40} />
          <div className="qrp-eyebrow">RISE CONDITIONING</div>
        </div>
        <h1 className="qrp-title">셀프 체크인</h1>
        <p className="qrp-lead">수업 시작 전, 앱으로 아래 QR을 비춰주세요.</p>

        <div className="qrp-qr">
          {/* 실제 인쇄 치수는 CSS가 아니라 이 인라인 style이 정한다 — PRINT_QR_MM 한 곳만
              고치면 안내 문구와 종이 위 크기가 같이 움직인다(둘이 어긋나면 근거가 무너진다).
              size는 viewBox만 만들면 되므로 값 자체는 의미가 없다. */}
          <QRCodeSVG
            value={token}
            size={512}
            level={QR_LEVEL}
            marginSize={4}
            bgColor="#ffffff"
            fgColor="#000000"
            title="셀프 체크인 QR"
            style={{ width: `${PRINT_QR_MM}mm`, height: `${PRINT_QR_MM}mm` }}
          />
        </div>

        {/* 문구는 앱 실물과 **글자 단위로** 맞춘다(P14 H2). 회원은 이 종이를 손에 들고 앱을
            뒤지므로, 없는 이름의 버튼을 적으면 그 사람은 못 찾고 데스크로 온다 —
            셀프 체크인이 덜어주려던 일이 그대로 돌아온다. 대조한 앱 코드:
              · 버튼 라벨·위치: next_booking_card.dart(홈 "다음 예약" 카드,
                '셀프 체크인 (데스크 QR 스캔)' / 성공 후 '체크인 완료')
              · 활성 조건: canCheckIn = |시작시각 - 지금| ≤ 30분 (home_repository_impl.dart)
              · 예약이 없으면 카드가 빈 상태라 **버튼 자체가 없다**(같은 파일 앞부분)
              · 성공 안내: '출석 완료! 세션 차감은 수업 완료 처리 후 반영돼요'(home_screen.dart) */}
        <ol className="qrp-steps">
          <li>
            <span className="qrp-num">1</span> 라이즈 앱 홈의 "다음 예약"에서{" "}
            <b>셀프 체크인 (데스크 QR 스캔)</b>을 누르세요.
          </li>
          <li>
            <span className="qrp-num">2</span> 카메라가 열리면 이 QR을 비춰주세요.
          </li>
          <li>
            <span className="qrp-num">3</span> <b>"출석 완료!"</b>가 뜨고 버튼이{" "}
            <b>체크인 완료</b>로 바뀌면 끝이에요.
          </li>
        </ol>

        <div className="qrp-rules">
          <p>
            버튼은 <b>수업 시작 앞뒤 30분에만</b> 눌려요(20:00 수업 → 19:30~20:30). 그 밖에는 흐리게
            보이고 눌리지 않습니다 — 고장이 아니에요.
          </p>
          <p>
            <b>다음 예약이 없으면 버튼도 보이지 않습니다.</b>
          </p>
          <p>
            수업을 고르실 필요는 없어요 — 그 시간의 <b>내 예약</b>을 앱이 알아서 찾습니다.
          </p>
          <p>버튼이 없거나 안 눌리거나 인식이 안 되면 데스크에 말씀해주세요.</p>
        </div>

        {/* 한 줄 유지(A4 1장 실측이 이 높이를 전제한다). 발급 일시가 앞이다 — 종이를 갈아 끼울지
            판단하는 값이 그쪽이고, 출력일은 종이가 얼마나 낡았는지만 말한다. */}
        <div className="qrp-foot">
          발급 {issuedLabel ?? "일시 미상"} · 출력 {todayStr()}
        </div>
      </div>
    </div>,
    document.body,
  );
}

// 발급 일시 표기 — "YYYY-MM-DD HH:MM".
//
// **화면과 종이가 같은 문자열을 보여야 대조가 성립**하므로 함수는 하나뿐이다.
// 분까지 적는 이유: 같은 날 두 번 발급했을 때 두 종이를 가를 수 있는 최소 해상도다. 이 해상도가
// 있으면 토큰 뒷자리 같은 **비밀 조각을 표식으로 쓸 이유가 사라진다**(그쪽은 정보를 흘리면서
// 구분력은 날짜·시각보다 나을 게 없다).
// 로컬 시간대로 찍는다 — 이 어드민의 다른 시각 계산(format.ts slotKeyStart)도 로컬=KST 전제다.
// 파싱 실패 시 원문 앞부분을 그대로 보여준다: 못 읽는 값을 "미상"으로 지우면 종이와 맞춰볼
// 근거까지 사라진다.
function formatIssuedAt(iso: string | null): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 16).replace("T", " ");
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
