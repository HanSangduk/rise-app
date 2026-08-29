---
id: P19
title: 어드민 브랜드 R 마크 적용 (파비콘 · 로그인 · 사이드바 · 인쇄 시트)
status: 완료
domain: admin
created: 2026-08-23
completed: 2026-08-23
---

## 목표

`design/brand/`의 R 마크(P19 브랜드 자산)를 어드민 네 자리에 심는다: ① 파비콘(없던 상태 —
브라우저 기본 아이콘이 떴다), ② 로그인 카드 타이틀 위, ③ 사이드바 텍스트 로고 옆,
④ 체크인 QR 인쇄 시트의 브랜드 헤더. 인쇄 시트는 A4 1장 실측이 깨지지 않아야 한다(P14 선례).
`app/`은 다른 팀 소관 — 건드리지 않았다. 배포도 하지 않았다.

## 결정 사항

- **파비콘과 화면 마크를 파일로 갈랐다.** `public/favicon.svg`는 크림 타일(둥근 사각형 rx 22%)
  위 마크, 화면·인쇄물은 `src/components/BrandMark.tsx`(배경 없는 획만). 용도가 다르면
  배경·배치 파라미터가 달라 한 파일로 겸하면 어느 쪽인가는 어긋난다 — brand README의
  마크/아이콘 분리와 같은 구도.
- **다크 패널 위에서는 ivory 톤(크림 획)으로 그린다.** 요청서는 "배경이 밝으니 획만"이었지만
  실물 로그인 카드는 다크(#15161d)다 — 네이비 원색 획은 명도가 붙어 가라앉는다(대비 ≈ 2:1).
  배경 타일을 깔지 않는다는 취지는 지키되 획 색만 크림(#F6F4EF)으로 — 크림은 브랜드 팔레트
  안의 색이라 "앱 색(레드)으로 다시 칠하지 말 것" 규칙과 충돌하지 않는다. 베이지 점은 양쪽
  톤에서 그대로다. 인쇄물(흰 종이)은 brand 톤(네이비) 원색.
- **사이드바에는 넣었다(판단 요청 항목).** 22px ivory, "RISE 어드민" 왼쪽. 실물 스크린샷으로
  확인 — 로그인과 같은 마크가 셸에서도 브랜드 블록을 잡아주고, 212px 사이드바에서 비좁지
  않다. <880px 가로 네비에서는 브랜드 블록 전체가 원래 숨어 마크도 함께 빠진다.
- **인쇄 시트 브랜드 헤더는 눈썹행을 대체.** "라이즈 컨디셔닝 센터" 텍스트 눈썹 →
  마크 9mm + "RISE CONDITIONING"(기존 qrp-eyebrow 자간 스타일 재사용). 종이의 주인공은
  QR이라 마크는 타이틀(32pt ≈ 11mm)보다 한 급 아래. 늘어난 높이만큼 `padding-top`
  12mm→7mm 보정.
- **인쇄 시 body 배경을 흰색으로 되돌리는 한 줄 추가**(P19 실측 중 발견한 기존 결함).
  인쇄 대화상자에서 "배경 그래픽"을 켜면 다크 body(#0c0d12)가 시트 아래 남은 자리에 검은
  띠로 찍혔다 — `body.has-qr-print { background:#fff }`(@media print 한정).

## 진행 단계

- [x] 파비콘 — `public/favicon.svg`(64 viewBox, 크림 타일 rx14, 마크 scale 0.216 중심 정렬) +
      `sips -Z`로 `favicon-32.png`·`apple-touch-icon.png`(마스터 1024에서 다운스케일) +
      `index.html` link 3종
- [x] `BrandMark.tsx` 신설(rise-mark.svg 지오메트리 이식, brand/ivory 톤)
- [x] 로그인 카드 마크 56px ivory / 사이드바 22px ivory
- [x] 인쇄 시트 브랜드 헤더 + padding-top 보정 + 인쇄 body 흰 배경
- [x] 검증 — 빌드·스크린샷·A4 1장 재실측(아래)

## 변경 파일

- `admin/public/favicon.svg` — **신규**(크림 타일 + 마크)
- `admin/public/favicon-32.png` · `admin/public/apple-touch-icon.png` — **신규**(gen/appicon-master.png에서 sips 다운스케일)
- `admin/index.html` — 파비콘 link 3종
- `admin/src/components/BrandMark.tsx` — **신규**(마크 컴포넌트, brand/ivory)
- `admin/src/features/Login.tsx` — 타이틀 위 마크 56px
- `admin/src/App.tsx` — 사이드바 브랜드 블록에 마크 22px
- `admin/src/features/CheckinQr.tsx` — 인쇄 시트 브랜드 헤더(마크 + RISE CONDITIONING)
- `admin/src/index.css` — `.qrp-brand` 치수(9mm), `padding-top` 12mm→7mm, 인쇄 body 흰 배경

## 검증

- `npm run build`(tsc 2회 + vite) 통과. dist에 favicon.svg·favicon-32.png·apple-touch-icon.png
  실재, index.html link 확인.
- **A4 1장 재실측**: 인메모리 백엔드(:8080, DEV_SEED) + vite dev를 띄우고 puppeteer로 실제
  화면(데모 대표 로그인 → 설정·직원 → 토큰 입력)에서 `page.pdf(preferCSSPageSize)` —
  pdfinfo **Pages: 1, A4**(594.96×841.92pt). 브랜드 헤더 포함, 푸터 아래 여유 ≈ 16mm(약 2줄,
  P14 실측과 같은 급). QR 80mm 고정이라 토큰 길이가 늘어도 페이지 높이는 불변(P14 근거 유지).
- **스크린샷 육안 확인**(scratchpad `brand/shots/`): 로그인(dist 정적 서빙) · 대시보드 사이드바 ·
  설정 화면 · 인쇄 시트 래스터 · 파비콘 128/64/32/16px(16px에서도 판독됨).

## 후속 작업

- 앱(Flutter) 쪽 아이콘 적용은 다른 팀 — `gen/appicon-*.png`가 준비돼 있다.
- 배포는 람이 직접(이번 작업에서 하지 않음).

## 참조

- `design/brand/README.md` · `design/brand/rise-mark.svg`(소스 오브 트루스)
- P14(`P14-center-policy-truth.md`) — 인쇄 시트 A4 1장 실측 선례
