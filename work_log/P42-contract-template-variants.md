---
id: P42
title: 계약서 템플릿 2종(신고/비대상) + 시설 신고 상태 선언 + 슬롯 갭 종결
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P42 — 계약서 템플릿 2종 (신고 / 비대상)

## 목표

람 요청: "시설업 신고한 거용이랑 안 한 거용 두 가지". 계약서doc이 이미 예정한 갈래(:818 "유권해석을 받았다면 이 행을 뺀다")를 P39 버전 아키텍처 위에 구현하고, 남아 있던 템플릿 슬롯 갭(약관 주소·보증보험·부가상품)을 닫아 **상태 선언 + 사업자 정보만 채우면 렌더까지 통하는** 완결 상태로 만든다.

## 결정 사항

- **선택지는 서식 취향이 아니라 신고 상태 선언** — 어드민 설정 3단: `unknown`(기본) / `reported`(+신고번호) / `exempt`(신고 대상 아님 — 유권해석·기구 미비치 강습 전용 확인). unknown이면 스탬프 스킵(P39 래치와 동일 철학 — 모르는 상태로 문서를 만들지 않는다). 이름을 "스튜디오"로 짓는 것은 업종 판단과 무관(실태 기준)임을 설정 화면 안내문에 명시 — P28 근거(면적 하한 없음·기구 요건 유권해석·§38②1 처벌) 요약.
- **템플릿 2종**: `pt-v1-reported`(현 pt-v1 계승 — 신고번호 행 유지) / `pt-v1-exempt`(당사자 표 신고번호 행 제거 + §A 전체 grep으로 체육시설법 의존 문구 조정 — 제20조④ 인용 등). 기존 `pt-v1`은 폐기(스탬프 이력 0 — 래치가 한 번도 안 켜짐, 안전).
- **신고 상태는 Business 밖** — P39 결정 6의 IsComplete 회귀(법정 문서 4장 초안 배너 부활)를 피해 centers 문서의 별도 절(`facility`)로. 머지 쓰기(P27 SavePolicy 교훈). 공개 응답(GET /v1/public/business) 비노출 — 키 집합 고정 테스트 불가침.
- **슬롯 갭 종결**: {{약관 게시 주소}} = 서버 상수(호스팅 배포 URL — P27 §F 기지값), {{보증보험 종류·보장내용}} = facility 설정 입력(빈 값 → 제20조③ 자체 설계대로 "가입하지 않았습니다"), {{부가상품 3종}} = 조문 대체로 슬롯 제거 — **시스템이 부가상품을 팔 수 없으므로**(Pass 모델에 부가상품 부재) "코드가 하는 것만 약속"(P28 원칙) + :1275 "없으면 조문을 통째로 대체(빈 표 금지)" 지시 이행. 부가상품 도입 시 새 템플릿 버전으로(버전 체계가 감당).
- 결과 requiredVarKeys: reported = 22 + 신고번호 + 약관주소 + 보증보험 = **25** / exempt = **24**. 양쪽 다 issuable=false 유지 — 발행 스위치는 여전히 람의 §F 체크리스트 뒤.
- 체결일은 계속 entityVars(P39 결정 3 불변).

## 진행 단계

- [x] 템플릿/앱: 변형 자산 2종 저작(§A 체육시설법 의존 전수 감사), 버전 표 갱신, 골든 재고정, 전체 스위트 그린(1097)
- [x] 백엔드: facility 절(타입·머지 저장·owner 전용 엔드포인트), 레지스트리 2종(25/24키), 조립 확장(신고번호·약관주소·보증보험 폴백), 상태별 버전 선택(unknown 스킵), 테스트·뮤테이션 10/10, API계약 v2.19
- [x] 어드민: 설정 → 시설 신고 카드(3단 라디오 + 조건부 신고번호 + 보증보험 입력 + 안내문), 빌드 그린
- [x] 오케스트레이터 교차검증 + 마감(2026-08-29) — ① **키셋 바이트 대조**: 백엔드 레지스트리(25키+체결일) == reported 자산 26슬롯 diff 무결(exempt는 양쪽 다 신고번호 단일 차이라 구성상 일치), 초과 1건은 헤더 주석 리터럴 `{{...}}`(렌더러가 주석을 슬롯 수집 전 스킵 — 무해 확인) ② **와이어 3자 일치**: domain/facility.go json 태그 == admin types == 계약 문서 ③ 3계층 직접 재실행 — 앱 1097 전건·백엔드 -count=1 전건·어드민 빌드 그린 ④ **타 세션 v2.17 중복 클레임 수리**: :2029 상담요청 섹션을 내용 무변경으로 v2.20 재번호 + 정정 주석, 최근 ptdesk 피어 세션 2곳에 알림 발송 ⑤ 어드민 카드 정독(저장 상태만 말하는 배지·3분기·안내문)

## 변경 파일

### 어드민 (완료)
- `admin/src/lib/types.ts` — `FacilityReportStatus`·`CenterFacility`·`EMPTY_FACILITY` 신설, `Center.facility?` 추가(**optional** — 백엔드와 병렬 작업·P41 배포 스큐 대비, 부재 시 미확인으로 폴백)
- `admin/src/lib/api.ts` — `saveFacility`(PUT /v1/center/facility, owner 전용 — 3필드 top-level 통 교체, 응답은 저장된 facility 그 자체)
- `admin/src/lib/queries.ts` — `useSaveFacility`(`keys.center` 무효화 — useUpdateCenterBusiness와 같은 규약: 같은 문서의 조각이라 키를 나누지 않는다)
- `admin/src/features/Settings.tsx` — "체육시설업 신고" 카드(사업자 정보 옆) + `FacilityEditForm`: 3단 라디오(미확인/신고함/신고 대상 아님) · reported 시 조건부 신고번호(필수) · 보증보험 Textarea(빈 값 = 제20조③ "가입하지 않았습니다" 폴백 placeholder) · 안내문 4행. 저장 규약은 BusinessEditForm 미러 — baseline 마운트 동결·touched·serverMoved 경고·성공 시 응답 재장전, 헤더 배지는 저장 상태만

### 템플릿/앱 (완료)
- `app/assets/legal/contract_pt_v1_reported.md` — 신설(440행). §A 계승 + 제5조 조문 대체(:1275 — 부가상품 슬롯 3종 제거, 조 번호·표제 유지로 넘버링 불변). 슬롯 26종(Vars 25 + {{계약 체결일}})
- `app/assets/legal/contract_pt_v1_exempt.md` — 신설(436행). reported + 감사 지점 5곳 조정(아래 감사 표). 슬롯 25종(Vars 24 + 체결일). 두 변형은 헤더 주석·감사 지점 밖에서 행 단위 동일(스크립트 diff로 생성 시 검증)
- `app/assets/legal/contract_pt_v1.md` — **삭제**(폐기 — 스탬프 이력 0, 래치 미점화라 재현 의무 대상 문서 없음)
- `app/lib/features/my/domain/contract_templates.dart` — 버전 표 {pt-v1} → {pt-v1-reported, pt-v1-exempt} (pubspec은 assets/legal/ 디렉토리 등록이라 무변경)
- `app/test/support/contract_render_fixture.dart` — 변형 2종 체계: exempt 24종이 공통 집합, reported = 스프레드 + 신고번호(25종). 부가상품 3키 제거
- `app/test/features/my/domain/contract_template_renderer_test.dart` — 골든 재고정: reported 143블록 리터럴(P39 146 − 제5조 대체 3) + exempt는 reported에서 **유도**(t2x9ll→t2x8ll 한 곳 — "구조 차이는 당사자 표뿐" 불변식을 골든화). 감사 그룹 신설(슬롯 인벤토리 = 빈 입력 MissingVars 전수 목록 26/25종, exempt 본문 체육시설 0곳, reported 신고번호 행 존재, 부가상품 슬롯 0곳)
- `app/test/features/my/domain/contract_templates_test.dart` — 신설: 표 매핑 2종 + 폐기 pt-v1 null + 미지 버전 null
- `app/test/features/my/presentation/widgets/contract_document_view_test.dart` — 레이아웃 가드 reported 고정(exempt는 새 블록 형태 없이 축소만이라 reported가 상한), 146→143블록
- `app/test/features/my/presentation/widgets/contract_sign_gate_test.dart` / `contract_detail_body_test.dart` — 기본 버전·FakeAssetBundle 키를 pt-v1-reported로 이동(시트는 표만 따라가 변형 로직 없음). DTO·repo 테스트의 'pt-v1' 문자열은 표 비의존 passthrough라 유지
- `docs/계약서_PT이용계약_v1.md` — §D-5 신설(변형 2종 체계·제5조 대체 근거·감사 결과 표). §A 본문 무변경(마스터 초안 유지 — 델타는 동결 전까지 자산이 보유)

### 백엔드 (완료)
- `backend/internal/domain/facility.go` — 신설: Facility(3단 상태 + Normalize 빈값→unknown + Validate: enum·reported⇒번호 필수·길이 40/200) + ErrInvalidFacility. Business 밖 별도 절인 근거 주석(P39 결정 6 회피)
- `backend/internal/domain/facility_test.go` — 신설: 정규화·검증 골든(경계값·원본 불변)
- `backend/internal/store/store.go` / `memory.go` / `firestore.go` — GetFacility/SaveFacility(미선언=unknown 기본값·읽기 무생성 — GetBusiness 규약. Firestore는 centers/{id}.facility 맵 **MergeAll 머지** — SaveBusiness와 동일 1줄 패턴)
- `backend/internal/store/conformance_test.go` — testFacilityCoexist: 기본값/왕복/**3자 비덮어쓰기 양방향**/절 통 교체(빈 칸 저장 반영)
- `backend/internal/api/contract_template.go` — **pt-v1 삭제**(스탬프 이력 0 근거 주석 + 저장 계약 렌더 판정은 앱 버전 표 몫), pt-v1-reported(25)/pt-v1-exempt(24) 등록, contractTermsURL·contractInsuranceNone 상수, contractVariantByStatus(상태→버전) + contractStampLatchOn(읽기 없는 사전 게이트) + contractTemplateForStatus(순수 선택, typed skip: latch_off/facility_report_status_unknown), 조립기 3계층에 fac 파라미터 + C-4 슬롯 3종(약관주소=상수, 보증보험=insurance 빈값→"가입하지 않았습니다", 신고번호=report_no)
- `backend/internal/api/service.go` — 스탬프 2지점(buildContractForPass·SendContract) 재배선: 래치(무읽기)→GetFacility→상태 선택→조립(facility 재사용 — 2회 읽기 창 제거). CenterResponse.Facility + GetCenter 읽기
- `backend/internal/api/service_facility.go` / `handlers_facility.go` — 신설: UpdateCenterFacility(owner 전용) + PUT /v1/center/facility(**응답 = 저장된 facility 3필드** — 어드민 saveFacility 재장전 규약에 정렬)
- `backend/internal/api/router.go` — 라우트 1줄 / `util.go` — ErrInvalidFacility 400 매핑 1줄 / `hookstore_test.go` — GetFacility 카운팅 래퍼
- `backend/internal/api/contract_template_test.go` — 레지스트리 재작업(25/24 바이트 고정·pt-v1 부재·latchOn=false·순수 스킵 사유), 조립 확장(exempt 키 부재/보험 폴백·공백/fac nil), 상수 핀 테스트
- `backend/internal/api/service_contract_stamp_test.go` — 픽스처 변형화 + seedFacility + 기존 5테스트 갱신 + 매트릭스(unknown×2·reported 25·exempt 24)·래치OFF×3상태·**GetFacility 0회 카운트**(latch-off 스토어 접근 불변)
- `backend/internal/api/service_facility_test.go` — 신설: 권한 403/검증 400/왕복·기본값/**머지 회귀 양방향**(P27 계열)/엔드포인트 상태코드 + 응답 3키 고정
- `docs/API계약_v1.md` — **v2.19** 신설(:2080 — facility 와이어, PUT 엔드포인트, 레지스트리 25/24 + pt-v1 폐기 근거, 선택 시맨틱 "모르는 상태로 문서를 만들지 않는다", 보증보험 degrade, 약관 URL 상수, 배포 순서)

## 검증

### 어드민
- `npm run build` 그린(tsc strict ×2 + vite) — 500kB 청크 경고는 기존 번들(712kB) 그대로, 이번 변경과 무관
- center 쿼리 타 소비처 전수 확인(Sales/Dashboard/Schedule) — 전부 `.policy`만 읽어 optional `facility` 추가로 깨지는 곳 없음
- reported + 빈 신고번호: 저장 버튼 비활성 + 인라인 warn 힌트(서버 400의 클라이언트 미러 — 집행자는 서버)
- facility 부재 응답(구서버): `facilityOf` → EMPTY_FACILITY(=미확인) 폴백 — 크래시가 아니라 "아직 미확인"으로 표시
- 자문자답: PUT 엔드포인트 미배포 스큐에서 저장 시 404 → ApiError 한국어 폴백이 폼 danger 라인에 표시(허용 가능한 스큐 동작) / 상태를 reported→exempt로 바꿔도 입력해 둔 신고번호는 폼·서버에 보존(재전환 시 유실 방지, 인쇄는 상태별)

### 템플릿/앱
- **§A 체육시설(법) 의존 전수 감사** — 현행 자산 grep("체육시설") 결과 본문 5곳 + 헤더 주석 1곳, [별지]에는 없음:

| # | 위치 | 내용 | reported | exempt 처분 |
|---|---|---|---|---|
| 1 | 당사자 표(:22) | 신고번호 행 + {{체육시설업 신고번호}} | 유지 | **행 제거**(:810 각주 갈래) |
| 2 | 제13조⑥(:289) | 체시법 §22·시행령 [별표 3의2] 인용 | 유지 | 인용 제거, 우선 적용 약속 유지 |
| 3 | 제13조⑥(:290) | 소비자분쟁해결기준**(체육시설업)** 라벨 | 유지 | 라벨만 제거(일반 인용화) |
| 4 | 제14조②(:298) | 시행령 [별표 3의2] 근거 인용 | 유지 | 인용 제거, 미이용분+1/10 가산 반환 약속 유지 |
| 5 | 제15조②(:308) | 시행령 §21의3 인용(연 15%) | 유지 | 인용 제거, 15% 약속·방판/전상 상향 경로 유지 |
| 6 | 제20조④(:373) | 체시법 §22①3 인용 | 유지 | 인용 괄호만 제거, 의무 문장 유지 |

- 슬롯 수 grep 검증: reported 고유 26/출현 38, exempt 고유 25/출현 37(주석 리터럴 제외). 차집합 = {체육시설업 신고번호} 하나 — 테스트로도 고정(빈 입력 MissingVars 전수 목록)
- `flutter analyze` 무결점 / **전체 스위트 1097 전건 그린**(개입 전 베이스라인 1082 확인 후 작업 — 신규 +15)
- 뮤테이션 5종 전부 사살: ① exempt 제20조④ 인용 재삽입→3건 실패 ② reported 신고번호 행 삭제→5건 ③ 버전 표 exempt→reported 오배선→templates 단위 테스트 1건(렌더러 테스트는 경로 직독이라 못 잡음 — 이 단위 테스트 신설 이유) ④ 픽스처 보증보험 키 제거→19건 ⑤ 제5조 부가상품 슬롯 재삽입→16건. 전 뮤테이션 원복 diff 무결
- 자문자답: 두 변형 **블록 수는 같은 143**(행 제거·인용 제거는 블록 단위가 아님) — 차이는 시그니처의 t2x9ll/t2x8ll로 드러나며 유도 골든이 고정 / 렌더러 파일 머리 주석의 "contract_pt_v1.md" 언급은 코드 불변 원칙(P42 지시)에 따라 그대로 — 동결 시점 P에서 일괄 정리

### 백엔드
- `go build ./...` · `go vet ./...` · `go test ./...` 전건 그린 + `go test -race ./internal/api/ ./internal/store/` 그린
- **P39 스탬프 테스트 의식적 갱신 목록**: `withIssuableContractTemplate`(단일 버전) → `withIssuableContractVariants`(reported/exempt 픽스처 셋, 실제 키 목록) / 22키 단언 → `contractPTv1ReportedVarKeys`(25) + kv 3종(약관주소 리터럴·보증보험·신고번호) / `gatherContractVars` 호출부 fac 파라미터 / latch-on 4테스트에 `seedFacility(reported)` 필수화(미선언이면 unknown 스킵이 설계) / latch-off 테스트에 reported 선언 추가(선택이 래치를 우회하지 않음 고정) / 레지스트리 테스트는 pt-v1 단언 → 2변형+pt-v1 부재로 전면 재작업. 골든 봉인 벡터("pt-v1" 문자열)는 무변경 — contractSeal은 레지스트리 비의존이라 유효
- **뮤테이션 10/10 전멸**: ①enum 가드 제거 ②reported⇒번호 제거 ③unknown→reported 폴백 ④보험 폴백 조건 반전 ⑤a reported 목록 신고번호 탈락 ⑤b exempt 목록 신고번호 잠입 ⑥latchOn always-true(→**GetFacility 0회 카운트 테스트**가 격추 — 이 뮤턴트만 잡는 자리라 신설) ⑦always-false ⑧owner 가드 제거 ⑨GetCenter facility 0값. 각각 표적 테스트 1개 이상 실패 확인 후 바이트 원복(scratchpad 백업 cp)
- 자문자답 해소: ③이 "결측 스킵에 가려지는" 마스킹 갭 발견 → "unknown + 번호 잔존" 서브테스트 신설(상태 스킵 vs 결측 스킵 구분) / PUT 응답 형태가 어드민 구현("저장된 facility 그 자체")과 어긋난 것을 교차검증에서 발견 → 핸들러·테스트·문서 정렬(전체 CenterResponse → 3필드 단독) / exempt 재전환 시 신고번호 보존 여부: 어드민은 폼 값 유지·서버는 "보낸 대로 저장"(Validate가 exempt+번호 허용) — 양립 확인
- 에뮬레이터 컨포먼스(-tags firestore_emulator)는 **미실행**: P41 세션의 에뮬레이터 프로세스 간섭 위험(java LISTEN 관측). SaveFacility는 SaveBusiness와 동일 1줄 MergeAll이라 위험 낮음 — 후속 1회 실행 항목으로

## 후속 작업

- 백엔드: P41 세션 종료 후 `firebase emulators:exec ... 'go test -tags firestore_emulator -count=1 ./internal/store/'` 1회 — testFacilityCoexist Firestore 러너 실검증
- 발행 스위치(두 변형 issuable=true)는 §F 체크리스트 + 앱 변형 자산 배포 확인 후 한 커밋으로(레지스트리 주석 참고)
- gofmt 잔여 2파일(`service_body_photo_reconcile_test.go`·`policy_test.go`)은 P42 밖 기존 상태 — 소유 세션에서 정리 권장

## 참조

- 근거: docs/계약서_PT이용계약_v1.md :810-818(신고번호 각주 — 면적 하한 없음·기구 유권해석·처벌), :400-407(제20조③ 보증보험 폴백), :1275(부가상품 조문 대체), [P28](P28-pt-contract-draft.md)
- 토대: [P39](P39-contract-document-machinery.md)(버전 레지스트리·렌더러·시트), [P27](P27-center-business-info.md)(centers 문서 구조·머지 쓰기 교훈)
