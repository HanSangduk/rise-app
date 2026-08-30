---
id: P50
title: 어드민 사용성 — 개발자만 아는 것을 대표에게 묻지 않는다
status: 완료
domain: admin
created: 2026-08-30
completed: 2026-08-30
---

# P50 — 어드민 사용성 (개발자 누수 일소)

## 목표

람의 지적에서 출발: *"운영 토큰을 어드민 쓰는 대표가 어떻게 알아? 자동 생성 버튼만 있으면 되지. 값 대조 같은 것도 실사용자한텐 필요 없잖아."* 체크인 QR은 [P49](P49-checkin-qr-server-issued.md)로 따로 닫고, **같은 병이 다른 화면에도 있는지** 전수 감사한 뒤 확정분을 수리한다.

정의한 결함 클래스: ① 대표가 알 수 없는 값을 입력하라고 요구 ② 실행 불가능한 안내(서버를 보라·명령을 치라·관리자에게 문의) ③ 내부 식별자·영문 enum·원시 오류를 화면에 노출 ④ 화면 문구의 개발 용어 ⑤ 서버가 이미 아는 것을 사람에게 묻거나 대조시키기 ⑥ 문제만 말하고 나갈 길이 없는 막다른 화면.

## 결정 사항

- **감사와 수리를 분리**하고, 수리는 파일 소유를 갈라 3개 에이전트 병렬(전역 오류 인프라 / 화면별 정직성 / 체크인 화면). 같은 파일을 두 에이전트가 만지지 않게 territory를 못박았고, 실제로 충돌 0건이었다(빌드 중 TS6133 교차 관측 1회는 상대 작업 중 상태로 확인 후 통과).
- **"관리자에게 문의하세요"는 전부 제거** — 이 제품에 관리자는 없다. 대표가 곧 관리자다. 제품이 아는 해결책이 있으면 그것을 말하고(퇴사 계정 → 설정·직원 → 재입사 처리), 없으면 **없다는 사실을 적는다**(로그아웃·로그인 반복으로 시간 버리지 않게).
- **지원 연락처는 만들어내지 않았다** — 세 자리(대표 권한 소실·이메일 로그인 차단·반복 크래시)에서 필요하지만 실재하지 않는다. 연락처 없이도 성립하는 문구로 쓰고 **후속으로 남긴다**(람이 채널을 정해야 실제 탈출구가 된다).
- **철회된 민감정보 동의는 어드민에서 다시 켤 수 없게 막았다** — 민감정보 동의는 정보주체 본인만 줄 수 있고, 기존 체크박스는 저장해도 `revoked_at`이 보존돼 **아무 일도 안 하면서 뭔가 한 것처럼 보이는 컨트롤**이었다. 읽기 전용 고지로 교체.
- 공용화 보류: `UNRESOLVED_STAFF`·`formatMonthLabel`은 로컬 중복 + 상호 참조 주석(두 번째 소비처가 생기면 `lib/format.ts`로 승격). 지금 승격하면 남의 파일을 건드려야 해서 병렬 작업과 충돌한다.

## 진행 단계

- [x] 전 화면 감사(읽기 전용) — H 7 · M 다수 · L 다수, "고쳐야 할 것 5순위"와 **"비슷해 보이지만 건드리면 안 되는 것"** 목록 동반
- [x] 수리 3갈래 병렬 + 오케스트레이터 직접 수리(티켓 번호 노출 3곳, `onRetry` 미배선 25곳, `text-accent` 없는 토큰, Schedule 인라인 문구, main.tsx 경계, 재동의 경로 명시)
- [x] 검증: 빌드 그린 · **프로덕션 번들 기준 누수 0건** · 재동의 경로 실재 확인

## 변경 파일

**전역 오류 인프라** — `lib/api.ts`(fetch·본문수신 2곳 try/catch → 한국어 정규화, 전달경로·5xx·409 문구 재작성), `components/ui.tsx`(ErrorState `onRetry` 옵션 + "오류:" 접두 제거), `components/ErrorBoundary.tsx`(신규), `App.tsx`·`main.tsx`(경계 2겹 — 프로바이더 안팎), `features/Login.tsx`(퇴사 계정 → 재입사 안내, 원시 코드·`e.message` 차단, 역할 한글화), `features/NoAccess.tsx`(대표 권한 소실 케이스 3번째 줄)

**화면별 정직성·데이터 무결** — `features/PoseSequenceEditor.tsx`(key 입력칸 삭제 + `mintKey` 생성 + 파일명 규칙 에러 제거 + 되돌리기 재동기화·2단 확인), `features/BodyPhotos.tsx`(철회 안내 사실화·판정 기준 `revoked_at` 단독), `features/Members.tsx`(uid 노출 → `(담당 미확인)`, `staffQ.isError` 배너 + 3분기, 철회 배지·수정 폼 잠금, enum·티켓·`refund` 문구, 계약 등록 비활성 사유), `features/Dashboard.tsx`(재등록 완료 실패 행 단위 노출, 새로고침 3쿼리 추가, 막다른 안내 재작성), `features/Sales.tsx`(`2026-08` → `2026년 8월`, "감췄어요" 사실 정정, 개발 용어 제거)

**오케스트레이터 직접** — `features/BodyPhotoLightbox.tsx`(`text-accent` → `text-brand`, P8 제거), `features/Settings.tsx`(P48 2곳·"폴백 경로" 제거), `features/Schedule.tsx`(인라인 오류 괄호 제거 — 완결 문장이 들어오게 됨), `admin/README.md`(P49로 뒤집힌 체크인 QR 서술 전면 갱신), `onRetry` 25곳 전량 배선, 재동의 경로를 회원 앱 실제 라벨로 명시

## 검증

- `npm run build` 그린. **프로덕션 번들 grep**: `CHECKIN_QR_TOKEN`·`sha256sum`·`관리자에게`·`owner/trainer`·`백엔드`·`8080`·`(P48)`·`(P8)`·`(P5)`·`API 연결 경로`·`동시 처리 충돌` **전부 0건**. `ErrorState` 미배선 잔여 0.
- **H1 실측**(에이전트가 esbuild로 `api.ts`를 번들해 Node에서 실행): 오프라인(Chrome/Safari)·본문 수신 중 끊김·SPA 폴백·404·503 6개 시나리오에서 렌더 문자열이 전부 한국어, 영문 잔재 0, 원문은 `console.error`에만. `main.tsx` retry 술어도 재실행 — status 0은 재시도 O, transport는 X.
- **재동의 경로 실재 확인**(에이전트가 "확인 필요"로 남긴 항목): 서버 `normalizeConsentTransition`이 `false→true`에서 `RevokedAt = nil`로 해제하고(service.go:489-495), 회원 앱 마이 탭에 **"민감정보(인바디·체형사진) 동의"** 행이 있다(contracts_row.dart:69-80). 어드민 문구가 이 경로를 그대로 짚도록 3곳 수정 — 잠금은 영구가 아니다.

## 후속 작업

- **지원 연락처 한 줄이 필요하다**(람 결정): 대표 권한 소실 / 이메일 로그인 차단 / 반복 크래시 세 자리는 연락처가 들어와야 진짜 탈출구가 된다.
- **센터 운영시간이 09~21시 하드코딩**(Schedule.tsx `DEFAULT_HOURS`) — 정책에 필드가 없어 새벽·야간 센터는 그 시간대 예약을 만들 수 없다. **서버 작업 필요**라 이번 웨이브에서 제외.
- **트레이너 프로필 사진이 URL 입력만 지원**(Settings) — 폰 사진에는 URL이 없어 사실상 넣을 방법이 없다. 체형사진 Storage 배관을 재사용하면 됨.
- 센터명이 하드코딩이라 대표가 입력한 상호(`business.biz_name`)를 무시한다(Settings 카드·헤더·로그인·index.html).
- 결정적 크래시 루프의 2차 탈출구(세션 비우기)는 `auth.tsx` 노출이 필요해 보류.
- `POSE_KEY_RE`는 이제 소비처 0(서버 규약 문서 역할로 존치 권고), `UNRESOLVED_STAFF`·`formatMonthLabel` 승격 후보.

## 참조

- 발단: 람의 체크인 토큰 지적 → [P49](P49-checkin-qr-server-issued.md)(서버 발급 전환)와 본 P(같은 병의 나머지)로 분리
- 패턴 출처: Schedule.tsx의 id 비노출 규약 · BodyPhotoLightbox의 오류 분류+재시도 · Members payConfirm 2단 확인 · [P40](P40-withdrawal-contract-closure.md) 행 단위 실패 노출
