---
id: P70
title: 관리 평면 센터 목록에 1호점(라이즈)이 안 보이던 것 — 기본 센터 상시 포함 (계약 v2.35)
status: 완료
domain: cross
created: 2026-09-08
completed: 2026-09-08
---

# P70 — 센터 관리 "등록된 센터가 없습니다" 검토

## 목표 (람 보고)
superadmin으로 센터 관리 탭을 열었더니 "아직 등록된 센터가 없습니다"가 떴다. 라이즈 센터가 운영 중인데.
"제대로 작업한 거 맞아? 교차 검증·자문자답."

## 교차 검증 결과
- **코드는 설계대로 동작했다** — `GET /v1/admin/centers`(v2.16, P41)가 상호 등록 문서만 돌려주고,
  라이즈는 상호 미등록(`GET /v1/public/center` → `name:""`, 2026-09-08 재실측). P65가 이 사실을 알고
  화면 각주로 설명하는 쪽을 택했고, api.ts·Centers.tsx 주석·README 모두 그렇게 적혀 있었다.
- **그 결정이 틀렸다.** 운영 중인 센터가 안 보이는 목록은 유령을 거른 게 아니라 진실을 거른 것이다.
  같은 저장소의 회원용 목록(v2.33 `joinCenterIDs`)은 이미 "기본 센터 ∪ 상호 등록 센터"로 만들어져
  있었는데 관리 평면만 옛 집합을 쓰고 있었다 — 불일치.
- superadmin은 상호를 직접 못 채운다(PUT /v1/center는 owner 전용, v2.27 결정 유지). 라이즈 상호는
  라이즈 대표 계정으로 설정 → 센터 신원에서 넣어야 한다.

## 결정 사항
- 서비스 `ListCenters`를 `joinCenterIDs`와 같은 집합으로: 기본 센터 맨 앞(상호 없으면 name:"" 그대로),
  나머지 상호 등록 센터 ID 오름차순, 중복 없음. 기본 센터 외 상호 미등록 문서는 여전히 유령으로 제외.
- 스토어 `ListCenters`는 건드리지 않음(유령 필터 규약 유지, `joinCenterIDs`도 그대로 사용).
- 어드민: 상호 빈 항목은 ID + "상호 미등록" 배지, created_at 제로값("0001-")은 "—", 각주 문구 교체.

## 자문자답
- 기본 센터가 유령일 수 있나 → 없다(config가 운영 센터로 선언). 문서가 없어도 GetCenter 규약으로 ID만 채워 오른다.
- 기본 센터가 상호를 등록하면 두 번 뜨나 → 스토어 목록에서 def를 건너뛰어 한 번만(테스트).
- created_at 제로값을 서버에서 지우나 → domain.Center의 time.Time은 omitempty 불가. 소비자가 어드민뿐이라 화면에서 접는다.
- 앱 영향 → 없음(superadmin 전용 경로). 앱 소스 변경 0.
- 다른 세션(P69, v2.34) 충돌 → api.ts·README는 국소 문자열 편집만, 계약은 v2.35 절 추가로 분리.

## 진행 단계
- [x] 백엔드 `ListCenters` 집합 변경 + 테스트 3건(미등록 기본 센터·등록 후 중복 없음·유령 제외)
- [x] 어드민 Centers.tsx 표시(배지·날짜·각주) + api.ts 주석
- [x] 계약 v2.35 절 · 백엔드 README 한 줄
- [ ] 배포(람): 백엔드 Cloud Run + 어드민 Hosting

## 변경 파일
- `backend/internal/api/service_admin.go` · `service_admin_test.go`
- `admin/src/features/Centers.tsx` · `admin/src/lib/api.ts`(주석)
- `docs/API계약_v1.md`(1835행 개정 표기 + v2.35 절) · `backend/README.md`

## 검증
- `go vet ./...` · `go test -race ./...` 전부 통과
- admin `tsc --noEmit` · `vite build` 통과
- gofmt 경고 `service_demo_seed_test.go`는 커밋된 타 세션 파일(내 변경 아님)

## 후속 작업
- 라이즈 상호·전화·주소 등록: 라이즈 대표 계정으로 설정 → 센터 신원(superadmin 불가).
- 배포 전까지 프로덕션은 빈 목록 그대로.

## 참조
- P41(v2.16 관리 평면) · P65(각주 결정) · P66(v2.33 joinCenterIDs) · P68(superadmin 네비)
