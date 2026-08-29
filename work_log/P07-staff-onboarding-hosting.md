---
id: P07
title: 트레이너 등록 + 어드민 호스팅 + 서버 감시
status: 완료
domain: cross
created: 2026-08-22
completed: 2026-08-22
---

# P07 — 트레이너 등록 · 어드민 호스팅 · 서버 감시

## 목표

P06으로 3계층이 실연동됐지만 **실사용은 아직 불가능**했다. 셋을 메운다:

1. **트레이너 등록** — 스태프 생성 API가 없어 대표가 실제 트레이너를 온보딩할 수 없었다
   (프로덕션 Firestore엔 owner 1명뿐, 지금까지 DEV_SEED가 가려주던 갭).
2. **어드민 호스팅** — 람의 로컬 개발 서버에서만 접근 가능했다. 어디서든 쓸 수 있게 올린다.
3. **서버 감시** — 백엔드가 죽어도 아무도 모른다. 상태 알림을 건다.

## 결정 사항

- **초대 방식 = 백엔드가 계정 생성, 비밀번호는 본인이 설정.** `POST /v1/staff`가 Firebase
  Admin SDK로 이메일 계정을 만들되(임시 랜덤 비번) **응답에 비밀번호를 담지 않고**, 어드민이
  생성 직후 클라이언트 SDK의 `sendPasswordResetEmail`로 초대 메일을 보낸다.
  근거: 백엔드에 메일 발송 인프라(SMTP·어댑터)가 없는데 Firebase 자체 메일러는 클라이언트
  SDK에서만 부를 수 있다. 임시 비번을 화면에 띄워 구두 전달하는 방식보다 안전하고,
  P06에서 로그인 화면에 넣은 "비밀번호를 잊으셨나요" 경로가 그대로 재발송 수단이 된다.
- **이미 있는 이메일이면 uid 재사용**(재초대 허용). 단 그 uid가 이미 이 센터 스태프거나
  회원으로 연결돼 있으면 409.
- **Firebase 유저 생성은 인터페이스 뒤로**(`UserProvisioner`) — 테스트가 SDK 없이 돌아야 하고,
  기존 `Authenticator`의 dev/prod 분기 방식과 대칭을 맞춘다.
- **어드민은 Firebase Hosting, API는 같은 도메인의 `/api`로 리라이트.** Cloud Run을 직접
  호출하지 않으므로 **CORS가 아예 발생하지 않는다**(프리플라이트 왕복도 사라짐).
  Hosting은 경로 접두사를 벗겨주지 못하므로 백엔드가 `/api/v1/*`도 받도록 라우터에 미러
  마운트를 둔다 — 그 덕에 개발(vite 프록시가 `/api`를 벗김)과 운영의 클라이언트 코드가
  완전히 동일해진다(`VITE_API_BASE` 기본값 `/api` 그대로).
- 서버 감시는 Cloud Monitoring uptime check + 알림 정책(이메일) — `/health` 대상
  (`/healthz`는 run.app에서 GFE가 가로챈다, P06).

## 진행 단계

- [x] 1. 계약 v1.8 절 정의(POST /v1/staff) + 실행 2팀 가동(백엔드·어드민) — 양쪽 완료
- [x] 2. 백엔드 라우터 `/api/v1` 미러 마운트(+`TestAPIPrefixMirror` 회귀 가드) + 배포
- [x] 3. Firebase Hosting 구성·배포(어드민 SPA + `/api` → Cloud Run 리라이트) —
      https://rize-218c1.web.app. firebase CLI가 ADC 계정 불일치로 403이라 Hosting REST로
      직행(버전 생성 → gzip 해시 업로드 → 확정 → 릴리스). 스크립트는 스크래치패드에 보존.
- [x] 4. Cloud Monitoring uptime check + 이메일 알림 정책 —
      `rize-api /health` 5분 주기 · 3개 리전(아시아·미국·유럽) 교차 확인,
      실패 시 `rize-api 다운 감지` 정책이 rizejoy91@gmail.com으로 발송(30분 후 자동 해제)
- [x] 5. 교차검증·자문자답 → 3계층 매트릭스 → 프로덕션 E2E(실제 트레이너 초대) **14/14 PASS**
- [x] 6. 문서(계약 v1.8·3 README·본 로그) 마감

## 변경 파일

**backend**
- `internal/domain/staff.go` — `StaffCreate`(+Normalize/Validate), `validateEmail`(net/mail),
  `isHexColor`, `Payout.Validate`, `DefaultPayout`, `StaffPalette`·`PickStaffColor`, `ErrInvalidStaff`
- `internal/api/provision.go`(신규) — `UserProvisioner` 인터페이스 + dev(이메일 sha256 결정적 uid)/
  Firebase(Admin SDK, 기존 계정 uid 재사용) 구현 + `tempPassword`(응답·로그에 남기지 않음)
- `internal/api/service.go` — `Service.users` + `CreateStaff`
- `internal/api/handlers_staff.go` · `internal/api/util.go`(`ErrConflict` 409 매핑) ·
  `cmd/server/main.go`(프로비저너 주입)
- `internal/api/router.go` — `POST /staff` + **`/api/v1` 미러 마운트**(v1 정의는 한 곳)
- `internal/api/service_test.go` — 스태프 테스트 8종 + `TestAPIPrefixMirror`(미러·인증·쓰기 경로)

**admin**
- `src/lib/types.ts`(`CreateStaffRequest`) · `src/lib/api.ts`(`createStaff` + **`ApiError`**로
  상태코드 보존 — 기존 호출부는 `.message`만 써서 하위호환) · `src/lib/queries.ts`(`useCreateStaff`)
- `src/features/Settings.tsx` — 버튼 활성화(owner 전용) + `InviteStaffModal`
  (생성 성공 후 `sendPasswordResetEmail`, 메일 실패만 따로 안내)

**인프라·문서**
- `firebase.json`·`.firebaserc`(신규) — Hosting + `/api` → Cloud Run 리라이트, 캐시 헤더
- `docs/API계약_v1.md` — **v1.8 스태프 초대** 절(엔드포인트·uid 확보 규칙·초대 메커니즘·배포 토폴로지)
- `backend/README.md`(엔드포인트·미러·감시) · `admin/README.md`(호스팅 절·초대 플로우·stale 항목 해소)

## 검증

- backend `go vet` 클린 · `go test ./... -race` 그린(스태프 8종 + 미러 1종 신규)
- admin `npx tsc --noEmit` exit 0 · `npm run build` exit 0
- **프로덕션 E2E 14/14 PASS**(실 Cloud Run + 실 Firestore + 실 Firebase Auth):
  201 생성 · 비밀번호/이메일 미노출 · `offdays:[]` · color 자동 배정(대표 `#60a5fa`와 겹치지 않는
  `#f43f5e`) · payout 반영 · **Firebase 계정 실제 생성**(uid 일치, password 공급자 부착 —
  재설정 메일 전제 충족) · 목록 즉시 노출 · **초대 직후 휴무일·프로필 수정 200**(원래 막혀 있던
  지점이 열렸다는 증명) · 재초대 409 · 호스팅 경유 `/api/v1` 동일 동작. 생성물 전부 정리 완료.
- 호스팅 스모크: SPA 200 · 딥링크 폴백 200 · `/api/v1/me` → 백엔드 401 JSON(리라이트 성공) ·
  정적 자산 `max-age=31536000, immutable`
- 감시: uptime check(`/health`, 5분, 3개 리전) + 알림 정책 enabled, 채널 1개 연결 확인

## 후속 작업

- **직원 정정·퇴사 처리 UI 없음** — 잘못 초대한 계정의 이름·역할·정산 수정과 비활성화 경로가
  계약에 없다. 초대는 열렸지만 되돌리기가 없는 상태 → 다음 트랙 1순위.
- 스태프 생성은 UserIndex → Staff 순서로 두 번 쓰기(트랜잭션 없음, JoinApprove와 같은 한계).
  중간 실패 시 인덱스만 남는데 같은 이메일 재호출로 자가치유된다 — 스토어 트랜잭션화 시 함께 정리.
- color 자동 배정은 read-then-write라 **동시** 초대 시 색이 겹칠 수 있다(1인 운영 규모에선 무해).
- 데모(X-Dev) 모드에서 초대하면 백엔드는 합성 uid만 만드는데 어드민의 재설정 메일은 실
  프로젝트로 나간다 — 이메일 열거 보호 때문에 조용히 성공해 "보냈어요"가 뜬다. 실계정 대표는 무관.
- 커스텀 도메인 연결 시 Hosting에 도메인 추가 + Firebase Auth 승인된 도메인 등록 필요.

## 참조

- work_log/P06-firebase-integration.md(실연동 전제) · docs/API계약_v1.md v1.7·v1.8
