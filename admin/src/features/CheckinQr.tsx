// 데스크 체크인 QR(P11) — 설정·직원 화면의 한 섹션. 대표 전용.
//
// 왜 대표가 토큰을 손으로 입력하는가:
// 서버는 self_qr 체크인에서 요청의 qr_token을 환경변수 CHECKIN_QR_TOKEN과 **문자열 그대로**
// 비교한다(service.go Checkin: `req.QRToken != s.cfg.CheckinQRToken` → 400). 그런데 그 값을
// 돌려주는 API는 없다 — 있으면 안 된다. 그래서 값을 아는 사람(대표)이 여기 입력하고, 이 화면은
// **그 문자열을 QR로 그리는 일만** 한다. 서버로 보내지 않고 localStorage에도 쓰지 않는다.
//
// 앱이 스캔한 문자열은 가공 없이 qr_token으로 실려 간다. 따라서 QR에는 URL도 JSON도 아닌
// **토큰 원문 하나만** 인코딩한다(접두사를 붙이면 서버 비교에서 그대로 틀린다).
import { useEffect, useId, useState } from "react";
import { createPortal } from "react-dom";
import { QRCodeSVG } from "qrcode.react";
import { Check, Eraser, Eye, EyeOff, Printer, QrCode, TriangleAlert } from "lucide-react";
import { BrandMark } from "@/components/BrandMark";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
} from "@/components/ui";
import { todayStr } from "@/lib/format";

// 서버 환경변수 이름 — 안내문과 ".env 한 줄 통째 붙여넣기" 감지에 함께 쓴다.
const ENV_KEY = "CHECKIN_QR_TOKEN";

// 오류정정 Q(25%). 근거: 이 QR의 최종 형태는 **데스크에 붙는 인쇄물**이라 지문·긁힘·조명 반사로
// 일부 모듈이 상시 훼손된다(화면에 띄우는 QR과 다른 조건). Q는 M(15%)보다 모듈이 늘지만,
// 아래 70mm 인쇄에서는 늘어난 뒤에도 모듈 한 변이 1mm를 크게 웃돌아(→ PRINT_QR_MM 주석)
// 밀도 비용이 실질적으로 0이다. 값이 공짜면 견고한 쪽을 고른다.
// (qrcode.react의 boostLevel 기본값 true라, 버전이 안 늘어나면 H로 자동 승격되기도 한다.)
const QR_LEVEL = "Q" as const;

// 인쇄 크기 80mm. 근거 두 가지(실측은 아래 숫자 그대로 headless Chrome PDF로 확인했다):
//  ① 모듈 크기 — 폰 카메라가 안정적으로 읽으려면 모듈 한 변 0.5mm 이상이 실무 하한이다.
//     기본 토큰(rise-desk-checkin, 17바이트)은 레벨 Q에서 버전 2(25모듈) + 규격 여백 4모듈×2
//     = 33칸 → 80/33 ≈ 2.4mm/모듈. 토큰이 64자로 늘어도 49칸 → 1.6mm/모듈이라 하한의 3배다.
//     즉 토큰 길이가 바뀌어도 이 크기는 안 무너진다(A4 한 장도 그대로 유지된다).
//  ② 스캔 거리 — QR 업계 통용 경험칙은 "인식 거리 ≈ 코드 한 변 × 10". 80mm면 약 80cm까지,
//     데스크에서 팔을 뻗어 대는 30~50cm를 충분히 덮는다.
const PRINT_QR_MM = 80;

// 화면 미리보기. 인쇄 전 눈으로 확인하는 용도라 크게 둘 이유가 없다.
const PREVIEW_PX = 188;

export function CheckinQrCard() {
  const inputId = useId();
  // 이 state가 토큰의 유일한 거처다. 새로고침하면 사라진다(의도).
  const [raw, setRaw] = useState("");
  const [revealed, setRevealed] = useState(false);

  const token = raw.trim();
  const issues = tokenIssues(raw);
  const cleaned = cleanToken(raw);
  const canClean = cleaned !== "" && cleaned !== raw;
  const { fingerprint, cryptoAvailable } = useTokenFingerprint(token);

  return (
    <Card className="md:col-span-2">
      <CardHeader>
        <CardTitle>
          <QrCode className="mr-1.5 -mt-0.5 inline h-4 w-4" />
          데스크 체크인 QR
        </CardTitle>
        <Badge tone="warn">저장 안 됨</Badge>
      </CardHeader>
      <CardContent>
        <p className="text-[12px] leading-[1.9]">
          회원이 앱으로 데스크의 QR을 비추면 스스로 출석이 찍힙니다. 서버는 QR에 담긴 문자열이
          운영 토큰(<code className="text-ink">{ENV_KEY}</code>)과 <b>한 글자도 다르지 않을 때만</b>{" "}
          통과시키고, 그 값을 응답으로 돌려주지는 않습니다 — 그래서 값을 아는 대표가 직접 입력합니다.
        </p>

        <div className="mt-3 grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto]">
          {/* ── 왼쪽: 입력 · 검증 ── */}
          <div className="min-w-0">
            <Label htmlFor={inputId}>운영 토큰 (서버 {ENV_KEY} 와 같은 값)</Label>
            <div className="flex gap-2">
              <Input
                id={inputId}
                // 어깨너머·화면공유·스크린샷에서 즉시 읽히지 않게 기본은 가린다.
                // (아래 "왜 가리는가" 문단 참고 — 이 값은 어차피 데스크에 붙는다.)
                type={revealed ? "text" : "password"}
                value={raw}
                maxLength={200}
                spellCheck={false}
                // "off"는 크롬이 비밀번호 칸에서 무시한다 — new-password라야 저장된 로그인
                // 비밀번호가 이 칸에 자동완성되는 사고(엉뚱한 QR 인쇄)를 막는다.
                autoComplete="new-password"
                // 저장소 기본 토큰의 **실값**을 예시로 쓰지 않는다(P14 L2) — 종전 placeholder가
                // 기본 토큰과 글자까지 같아서, 값을 모르는 사람이 그대로 따라 쳐도 통과할 수 있었다.
                placeholder="서버에 설정한 값을 그대로 입력하세요"
                onChange={(e) => setRaw(e.target.value)}
              />
              <Button
                size="md"
                variant="outline"
                className="shrink-0"
                onClick={() => setRevealed((v) => !v)}
                aria-pressed={revealed}
              >
                {revealed ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                {revealed ? "가리기" : "보기"}
              </Button>
            </div>

            <p className="mt-1.5 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
              <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
              입력한 값은 <b>이 화면 밖으로 나가지 않습니다</b> — 서버로 보내지도, 브라우저에
              저장하지도 않아요. 새로고침하거나 다른 메뉴로 옮기면 <b>사라집니다</b>. 저장 기능이
              빠진 게 아니라, 토큰이 브라우저 저장소·백업·로그에 남지 않게 한 겁니다. 인쇄하고 나면
              다시 입력할 일이 거의 없어요.
            </p>

            {/* 이상 없음도 말해준다 — 경고가 안 뜬 게 "검사를 안 한 것"인지 "통과한 것"인지
                침묵으로는 구분되지 않는다. 다만 이건 문자열 형식 점검일 뿐, 서버 값과 같은지는
                아래 지문 대조가 답한다. */}
            {token !== "" && issues.length === 0 && (
              <p className="mt-2 text-[10.5px] text-ok">
                <Check className="mr-1 -mt-0.5 inline h-3 w-3" />
                눈에 안 보이는 공백·따옴표 같은 흔한 붙여넣기 사고는 없습니다({[...token].length}자).
              </p>
            )}

            {issues.length > 0 && (
              <div className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2">
                <div className="flex items-center gap-1 text-[11.5px] font-extrabold text-warn">
                  <TriangleAlert className="h-3.5 w-3.5" /> 값을 한 번 확인해주세요
                </div>
                <ul className="mt-1 space-y-0.5 text-[10.5px] leading-[1.7] text-muted">
                  {issues.map((t) => (
                    <li key={t}>· {t}</li>
                  ))}
                </ul>
                {canClean && (
                  <Button size="sm" variant="outline" className="mt-2" onClick={() => setRaw(cleaned)}>
                    <Eraser className="h-3.5 w-3.5" /> 자동으로 정리하기
                  </Button>
                )}
              </div>
            )}

            {/* 오입력 검증 — 대표가 값을 틀리게 넣으면 회원 화면엔 "체크인 실패"만 뜬다.
                서버에는 토큰을 확인해주는 API가 없고(있으면 안 되고), owner 계정으로 self_qr을
                시험 호출하면 토큰 비교 이전에 403이 난다(회원만 허용). 그래서 대조는 값 자체가
                아니라 **지문**으로 한다 — 채팅·캡처에 남겨도 안전하고 한 글자 차이도 잡힌다. */}
            <div className="mt-2.5 rounded-[10px] border border-line bg-panel-2 px-3 py-2.5">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="text-[11.5px] font-extrabold">붙이기 전에 값 대조하기</span>
                <span className="font-mono text-[13px] font-extrabold tracking-[0.18em] text-brand">
                  {token === "" ? "—" : cryptoAvailable ? (fingerprint ?? "계산 중…") : "표시 불가"}
                </span>
              </div>
              {cryptoAvailable ? (
                <>
                  <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
                    서버(백엔드가 도는 머신)에서 아래 한 줄을 실행해 같은 8자가 나오면 값이 정확히
                    일치합니다. 다르면 QR을 붙이지 마세요.
                  </p>
                  <pre className="mt-1.5 overflow-x-auto rounded-[8px] bg-bg px-2.5 py-2 font-mono text-[10.5px] leading-[1.7] text-ink">
                    {`# 서버 셸에 환경변수가 떠 있을 때 (macOS는 sha256sum 대신 shasum -a 256)\nprintf %s "$${ENV_KEY}" | sha256sum | cut -c1-8\n\n# .env 파일만 있을 때 (값을 따옴표로 감쌌다면 따옴표는 빼고 계산하세요)\ngrep -m1 '^${ENV_KEY}=' .env | cut -d= -f2- | tr -d '\\n' | sha256sum | cut -c1-8`}
                  </pre>
                  <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
                    <b className="text-ink">echo가 아니라 printf %s</b> 입니다 — echo가 끝에 붙이는
                    줄바꿈 한 글자 때문에 값이 같아도 지문이 달라집니다. 지문은 SHA-256 앞 8자리라
                    토큰 자체를 복원할 수 없습니다.
                  </p>
                </>
              ) : (
                <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
                  지문은 보안 컨텍스트(https 또는 localhost)에서만 계산됩니다. 지금은 그냥 http로
                  접속 중이라 브라우저가 계산 기능을 잠갔어요 — https 주소로 다시 열면 표시됩니다.
                </p>
              )}
            </div>

            <p className="mt-2.5 text-[10.5px] leading-[1.8] text-muted">
              <b className="text-ink">왜 기본은 가려두나</b> — 이 토큰은 어차피 데스크에 붙는 값이라
              지켜야 할 비밀이 아닙니다. 실제 방어선은 로그인한 <b className="text-ink">본인 계정</b>과{" "}
              <b className="text-ink">±30분 시간창</b>이에요. 다만 평문은 캡처 한 장·화면공유 몇 초로
              그대로 퍼지니 기본만 가려둡니다. 반대로 "비밀번호처럼 다뤄야 하나" 걱정하며 인쇄를
              망설일 필요도 없습니다.
            </p>
          </div>

          {/* ── 오른쪽: 미리보기 · 인쇄 ── */}
          <div className="flex flex-col items-center gap-2 lg:w-[248px]">
            <div className="flex h-[212px] w-[212px] items-center justify-center rounded-[13px] border border-line bg-white">
              {token === "" ? (
                <span className="px-4 text-center text-[11px] leading-[1.7] text-[#6b7280]">
                  토큰을 입력하면
                  <br />
                  여기에 QR이 그려집니다
                </span>
              ) : (
                // 항상 흰 바탕 · 검은 모듈. QR 규격은 "밝은 배경 위 어두운 모듈"이고, 반전은
                // 스캐너마다 되기도 안 되기도 한다 — 다크 테마를 QR 안까지 끌고 오지 않는다.
                <QRCodeSVG
                  value={token}
                  size={PREVIEW_PX}
                  level={QR_LEVEL}
                  marginSize={4}
                  bgColor="#ffffff"
                  fgColor="#000000"
                  title="데스크 체크인 QR 미리보기"
                />
              )}
            </div>
            <p className="text-center text-[10.5px] leading-[1.7] text-muted">
              오류정정 {QR_LEVEL}(25%) · 인쇄 {PRINT_QR_MM}mm
              <br />
              데스크 거리(30~50cm)에서 여유 있게 읽히는 크기예요.
            </p>
            <Button className="w-full" disabled={token === ""} onClick={() => window.print()}>
              <Printer className="h-4 w-4" /> A4 안내문 인쇄
            </Button>
            <p className="text-center text-[10.5px] leading-[1.7] text-muted">
              사이드바·헤더는 인쇄되지 않습니다. 토큰을 입력한 이 화면에서는 브라우저 인쇄(⌘/Ctrl+P)도
              같은 안내문 한 장으로 나옵니다.
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
              · 서버의 {ENV_KEY}를 바꾸면 <b className="text-ink">이미 붙여둔 QR은 그 즉시 무효</b>가
              됩니다. 토큰을 교체했다면 새로 인쇄해 갈아 끼우세요.
            </li>
          </ul>
        </div>
      </CardContent>

      {/* 인쇄 시트는 화면에서 늘 숨어 있고(#checkin-qr-print { display:none }) 인쇄할 때만 뜬다.
          토큰이 있을 때만 마운트한다 — 다른 화면에서 ⌘P를 눌렀는데 빈 종이가 나오지 않게. */}
      {token !== "" && <PrintSheet token={token} fingerprint={fingerprint} />}
    </Card>
  );
}

// ── 인쇄 시트(A4 1장) ──────────────────────────────────────────────────
//
// document.body로 포털한다. 어드민 셸(#root) 안에 두고 "나머지를 전부 숨기는" CSS를 쓰면
// 숨긴 요소가 차지한 높이 때문에 빈 페이지가 따라 나온다 — 셸과 시트를 body의 형제로 갈라두면
// 인쇄 시 #root 하나만 display:none 하면 끝이다(index.css 하단 참고).
//
// 인쇄물은 **회원이 읽는 글**이다 — 운영자용 용어(토큰·confirmed·환경변수)를 쓰지 않는다.
// 토큰 평문도 싣지 않는다: QR이 이미 그 값을 나르고, 종이에 글자로 적으면 지나가는 사람이
// 손으로 베껴 갈 수 있다(붙여두는 값이라 치명적이진 않지만 적을 이유가 없다).
// 대신 지문 8자만 작게 남긴다 — 토큰을 교체했을 때 붙어 있는 종이가 구버전인지 구분하는 표식.
function PrintSheet({ token, fingerprint }: { token: string; fingerprint: string | null }) {
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
            padding-top 12mm→7mm 보정으로 유지, 아래 .qrp-sheet 주석 참고). */}
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

        <div className="qrp-foot">
          코드 {fingerprint ?? "—"} · {todayStr()} 출력
        </div>
      </div>
    </div>,
    document.body,
  );
}

// ── 토큰 문자열 점검 ────────────────────────────────────────────────────

// 붙여넣기 사고를 화면에서 잡는다. 서버 비교는 문자열 완전 일치라 아래 항목 하나하나가
// 그대로 "회원은 실패만 보고 이유는 모르는" 상태를 만든다.
// 자동으로 고치지 않는 이유: 운영 토큰에 진짜 공백이 들어 있을 수도 있다. 알려주고,
// 고치는 건 대표가 버튼으로 결정한다.
function tokenIssues(raw: string): string[] {
  const out: string[] = [];
  if (raw === "") return out;
  const t = raw.trim();
  if (t === "") {
    out.push("공백만 입력돼 있어요.");
    return out;
  }
  if (raw !== t) {
    out.push("앞이나 뒤에 공백·줄바꿈이 붙어 있어요 — 눈에 안 보이지만 서버 값과 달라집니다.");
  }
  if (new RegExp(`^${ENV_KEY}\\s*=`, "i").test(t)) {
    out.push(`.env 한 줄을 통째로 붙여넣은 것 같아요 — "${ENV_KEY}=" 뒤의 값만 필요합니다.`);
  }
  if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'")))) {
    out.push("따옴표로 감싸여 있어요 — .env의 따옴표는 값에 포함되지 않습니다.");
  }
  if (/\s/.test(t)) {
    out.push("값 가운데에 공백이나 줄바꿈이 있어요 — 의도한 게 아니라면 지워주세요.");
  }
  if (/[^\x20-\x7E]/.test(t)) {
    out.push(
      "영문·숫자·기호가 아닌 문자(한글·이모지 등)가 섞여 있어요 — QR·스캐너·서버를 거치며 인코딩이 어긋날 수 있으니 서버 토큰을 ASCII로 바꾸는 편이 안전합니다.",
    );
  }
  return out;
}

// "정리하기" 버튼이 만들 값 — 앞뒤 공백 제거 → ENV_KEY= 접두사 제거 → 감싼 따옴표 한 겹 제거.
// 값 가운데 공백과 비ASCII는 건드리지 않는다(의도한 값일 수 있고, 지우면 조용히 다른 QR이 된다).
function cleanToken(raw: string): string {
  let v = raw.trim();
  v = v.replace(new RegExp(`^${ENV_KEY}\\s*=\\s*`, "i"), "").trim();
  if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
    v = v.slice(1, -1).trim();
  }
  return v;
}

// SHA-256 앞 8자리. crypto.subtle은 보안 컨텍스트(https·localhost)에서만 존재한다 —
// 평문 http로 열었을 때 조용히 빈 값이 되지 않도록 가용 여부를 함께 돌려준다.
function useTokenFingerprint(value: string): {
  fingerprint: string | null;
  cryptoAvailable: boolean;
} {
  const cryptoAvailable = typeof globalThis.crypto?.subtle?.digest === "function";
  const [fingerprint, setFingerprint] = useState<string | null>(null);

  useEffect(() => {
    if (!cryptoAvailable || value === "") {
      setFingerprint(null);
      return;
    }
    let alive = true;
    void (async () => {
      try {
        const buf = await globalThis.crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(value),
        );
        const hex = Array.from(new Uint8Array(buf))
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("");
        if (alive) setFingerprint(hex.slice(0, 8));
      } catch {
        if (alive) setFingerprint(null);
      }
    })();
    return () => {
      alive = false;
    };
  }, [value, cryptoAvailable]);

  return { fingerprint, cryptoAvailable };
}
