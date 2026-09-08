---
id: P68
title: superadmin 로그인 시 "센터 관리" 탭이 안 뜨고 대시보드 403이 첫 화면이 되던 버그
status: 완료
domain: admin
created: 2026-09-08
completed: 2026-09-08
---

# P68 — superadmin 네비 갱신 누락

## 목표 (람 보고)
superadmin으로 어드민에 로그인하니 `forbidden: superadmin은 관리 평면(/v1/admin/*)만 사용할 수 있어요`가 뜨고,
왼쪽 메뉴에 "센터 관리" 탭이 없다.

## 결정 사항
- 원인 1: `AdminShell`의 `nav` useMemo deps가 `[isOwner]`뿐. 셸은 로그인 화면 단계에서 이미 마운트돼
  첫 렌더(me=null)에 트레이너용 NAV로 굳고, 이후 me가 superadmin으로 확정돼도 isOwner는 false 그대로라
  재계산이 안 됐다 → "센터 관리" 없는 트레이너 메뉴.
- 원인 2: 섹션 되돌리기 effect가 무조건 `"dash"`로 보냄. superadmin nav에는 dash가 없어 대시보드가
  렌더되고 센터 API가 403.
- 배포된 번들(rize-218c1.web.app)에도 같은 코드가 있으므로 재배포 전까지 프로덕션에서 재현된다.

## 진행 단계
- [x] deps에 `isSuperadmin` 추가
- [x] 섹션 폴백을 `nav[0].id`로 (superadmin → centers, 나머지 → dash 동일)
- [x] tsc · vitest · vite build 통과

## 변경 파일
- `admin/src/App.tsx` — nav useMemo deps, 섹션 폴백

## 검증
- `npx tsc --noEmit` 통과 · `npx vitest run` 통과 · `npm run build` 성공
- 자문자답: 일반 스태프 경로는 nav[0]이 항상 "dash"라 동작 변화 없음. superadmin은 첫 렌더가 트레이너
  NAV여도 me 확정 직후 memo가 재계산되어 effect가 "centers"로 보낸다.

## 후속 작업
- 어드민 Hosting 재배포(람 실행, `deploy-hosting.sh`) — 배포 전까지 프로덕션은 그대로.
- 임시 우회 없음: 프로덕션 현재 번들은 탭 자체가 안 뜬다.

## 참조
- P65(superadmin 셸 신설) · backend/internal/api/auth.go `superadminAllowedPath`
