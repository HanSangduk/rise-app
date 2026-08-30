---
id: P39
title: 계약서 기계 축(TemplateVersion·Vars·sha256 봉인·앱 열람) — 발행 래치 꺼진 채 완비
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P39 — 계약서 기계 축 (발행 래치 꺼진 채 완비)

## 목표

P28 §D 렌더링 설계(버전 고정 템플릿 + 변수 스냅샷 + 해시)의 **기계 축 전체를 구현**하되, 발행은 열지 않는다. 착수 판정(별도 분석, 2026-08-29): 29슬롯 중 17(C-1 계약·패스·회원·결제 + C-2 정책)은 어떤 결정도 없이 조립 가능, P27 6칸은 파이프만, 신규 3슬롯·부가상품 3슬롯은 미결. **실서명 0건인 동안 템플릿 교체가 자유**라 지금 지어도 재작업이 없고, 람 결정 2건(체육시설업 신고 여부·사업자 정보 등록) 후 발행 래치 한 줄만 켜면 된다.

## 결정 사항

(§D가 침묵하는 6곳 — 자문자답으로 확정, 근거 포함)

1. **발행 게이트 대신 발행 래치** — 서버 템플릿 레지스트리에 pt-v1을 `issuable=false`로 등록. 래치가 꺼진 동안 send/발급이 TemplateVersion·Vars를 **아예 스탬프하지 않는다** → 다운스트림 전부 오늘 동작 그대로(요약 고지 서명 = P28이 적법화한 현행). 미완성 사업자 정보로 send를 400으로 막는 안(보수 게이트)은 기각 — 발급(CreatePass)이 계약 자동 생성을 겸하므로 게이트가 **회원권 발급 자체를 차단**하는 부작용. "(미정)"이 인쇄된 계약서(방판법 §30 기재 누락)도, 발급 차단도 아닌 제3의 길: 스탬프 자체를 안 한다.
2. **재발송 = Vars 재확정, 서명 = 동결** — §D ⑤ 문언 그대로("send 시점에 Vars를 채워 두고, 서명은 그것을 확정"). 이미 Vars가 있는 sent의 재발송도 재확정한다 — 회원이 서명 화면에서 보는 것은 언제나 저장된 Vars 렌더이므로 "본 것 = 서명한 것" 불변식(D-4)이 유지된다. 배포 전 sent 잔존 계약도 재발송으로 Vars를 얻는다(§C 마이그레이션 구멍 해소).
3. **{{계약 체결일}}은 Vars 밖** — send 시점엔 SignedAt이 없다. 서명 직전 보강(해시 입력 순서 의존)도 배제하고, 엔티티 필드(signed_at — sha256과 **같은 트랜잭션에서** 기록되는 불변 증적)에서 렌더한다. 해시는 "send가 확정한 것"만 덮는다는 원칙이 깨끗하게 유지된다. 문서 :781의 "SignedAt, 미서명이면 FirstSentAt"은 표시 규칙으로 그대로.
4. **{{납부일정}} 직렬화 포맷 명세 후 동결** — canonical_json 해시 입력이라 사후 변경 불가. "n회차 {금액}원 ({YYYY-MM-DD} 납부예정|납부완료)" 행을 "\n" 결합. API계약 **v2.18**에 명세 + 골든 테스트로 고정 (계획 당시 v2.16이었으나 P41·P40이 v2.16·v2.17을 선점 — 번호만 이동, 내용 동일).
5. **렌더러는 자체 결정적 부분집합 렌더** — 마크다운 패키지 의존 배제(flutter_markdown 계열은 버전에 따라 렌더가 변해 §D "언제나 같은 결과"와 상충 + P32 CustomPainter 선례). 템플릿이 실제 쓰는 문법(h1-h3·표·굵게·목록·구분선·문단)만 파싱·렌더, 골든 테스트로 고정. 미지 문법 발견 시 렌더 거부(모르는 것을 아는 척 안 함).
6. **Business 신규 3필드(신고번호·약관 게시 주소·보증보험) 이번에 안 넣음** — `IsComplete`가 전 칸 판정(businessFieldCount=12)이라 필드를 더하는 순간 **이미 완성이던 법정 문서 4장의 초안 배너가 되살아난다**(P27 회귀). 완성 판정 스코프 분리(문서용 vs 계약용) 설계와 함께 결정1 이후로.

(부수 확정)
- 사업자 6칸(P27 기존)은 Vars에 **얼린다**(D-4 재현성 불변식 — legal 문서처럼 실시간 조회하면 서명 당시 문서가 재현 안 됨). 래치가 켜진 뒤 사업자 정보가 미완이면 그 send는 스탬프를 건너뛴다(오늘 경로) — 조용한 열화가 아니라 문서에 명기된 완성 조건.
- **스탬프 시점 현실(백엔드 구현 중 확정)**: 발급(=자동 send)도 스탬프를 시도하지만, 확정 플로우상 결제 기록이 발급 **뒤**라 결제 2키(결제방법·납부일정)가 비어 전부-아니면-전무 가드가 통상 스킵한다 — **첫 완전 스탬프는 결제 기록 후 운영자의 재발송에서 찍히는 것이 정상 경로**(결함 아님, v2.18에 명기). 발급 경로만 스탬프에서 빼지 않은 이유: 스킵은 가드의 판정이지 경로의 예외가 아니어야 두 send 경로가 같은 규칙을 갖는다.
- **불완전 재발송의 보존 규약(백엔드 구현 중 확정)**: 스탬프가 성립하지 않는 재발송(래치 OFF·조립 불완전)은 기존 TemplateVersion/Vars를 **건드리지 않는다** — 이미 완전한 문서를 받아 본 회원의 열람물을 나중의 조립 불가능해진 재발송이 파괴하면 안 된다. 마지막 완전 스탬프가 살아남고, 서명은 그것을 봉인한다(v2.18 + 코드 주석 + 전용 테스트로 고정 — 뮤테이션 패스에서 이 테스트가 유일 방어선임을 실증).
- {{위약금율}}은 재확정에서도 안 움직인다 — 출처가 Policy가 아니라 Contract.PenaltyRate 스냅샷(§C 비고·P14). 재발송 재확정은 C-2 정책 5종에만 미친다(전용 대조 테스트).
- 어드민 열람 화면은 이번 범위 밖(§D에 화면 설계 부재 — 발명하지 않는다). P36 H "어드민 내용 열람 불가"의 어드민 반절은 후속 P로.
- sha256 비어 있음 ⟺ 본문 렌더 없이(요약 고지로) 진행된 계약 — 거짓 신호 없음. pdf_path는 §D ③대로 계속 비워 둔다.
- waived_at 트랜잭션 접합은 결제 도메인(PayInstallment 원자화) 후속 유지 — 계약 축 아님.

## 진행 단계

- [x] P37·P38 적대 리뷰 완료 대기(파일 충돌 방지) + 확정 결함 선반영 — P37 SHIP·P38 FIX-FIRST → 확정분은 [P40](P40-withdrawal-contract-closure.md)으로 선반영 완료
- [x] 백엔드(2026-08-29): Contract +TemplateVersion·Vars, 템플릿 레지스트리(issuable 래치, pt-v1 요구 슬롯 22종), send/발급 Vars 조립(래치 OFF 불변 명시 테스트 포함), SignContract sha256 봉인, canonical_json + 골든 테스트(독립 python 재도출), 뮤테이션 6/6 kill
- [x] 앱 — 렌더러 슬라이스(2026-08-29): 템플릿 자산 번들(가버전, §A 원문 바이트 동일 + pubspec 최초 assets: 키), 결정적 부분집합 렌더러(모델·파서·뷰) + 내용 골든 테스트 35개 + 뮤테이션 5/5 kill
- [x] 앱 — 시트 슬라이스(2026-08-29): DTO/모델/리포지토리에 template_version·vars·first_sent_at 스레딩, 버전→자산 표(미지 버전 = 렌더 금지 + 업데이트 안내), 서명 시트 전문 스크롤 + 끝-스크롤 후 체크박스 활성(짧은 문서는 첫 레이아웃에서 읽음 처리), 상세 시트 "계약서 본문 보기/접기", 레거시(문구 verbatim)·미지버전·표시불가(정직 고지) 분기, 뮤테이션 6/6 kill
- [x] 문서 — 백엔드 몫(2026-08-29): API계약 **v2.18**(스키마·해시 공식·직렬화 포맷·래치 규약·보존 규약 — v2.16·v2.17은 P41·P40 선점으로 번호 이동), 계약서doc §C-3 stale 정정
- [x] 문서: backend/README.md 갭 서술 갱신(오케스트레이터, 2026-08-29) — "sha256 채우는 코드 0곳"이 P39 이후 거짓이 됨 → 래치 뒤 완비 + "sha256 빈 서명 = 요약 고지 동의 기록" 신호로 재서술
- [x] 검증: 오케스트레이터 교차검증(2026-08-29) — 3계층 현재 트리에서 직접 재실행: 앱 `flutter analyze` 클린 + **1082 전부 통과**, 백엔드 `go test ./...` 전 패키지 ok, 어드민 빌드 그린. 서명 시트 게이트(래치·짧은 문서·로딩 중 닫힘·폴백 비차단)·봉인 지점(service.go:2780)·레지스트리 래치 OFF·v2.18 절 정독 확인. 각 슬라이스 뮤테이션 6/6·5/5·6/6 kill 보고 수령

## 변경 파일

**앱 렌더러 슬라이스 (2026-08-29)**

- `app/assets/legal/contract_pt_v1.md` — 신규. 계약서doc §A(34~479행, 23개조 + [별지]) 원문 바이트 동일 추출 + 가버전 표시 HTML 주석 2행. 슬롯 29종 = §C 목록과 대조 일치
- `app/pubspec.yaml` — `flutter.assets:` 키 신설(`assets/legal/`) — 이 프로젝트 최초의 assets 등록(종전 brand PNG는 런타임 미번들이 맞았다, P32)
- `app/lib/features/my/domain/contract_render_model.dart` — 신규. 블록 모델(헤딩·문단·인용·목록·표·펜스·수평선) + sealed 결과(Ready / UnknownSyntax·MissingVars·SlotSourceConflict), 전 타입 값 동등성(결정성 deep-equal용)
- `app/lib/features/my/domain/contract_template_renderer.dart` — 신규. 결정적 파서/치환. §A 전수 인벤토리 밖 문법은 렌더 거부(결정 5). 슬롯 입력은 `vars`/`entityVars` 두 맵 — {{계약 체결일}}이 Vars 밖(결정 3)임을 시그니처가 강제, 겹키는 우선순위 대신 거부
- `app/lib/features/my/presentation/widgets/contract_document_view.dart` — 신규. 블록 → 위젯(스크롤은 호출자 몫 — 서명 시트의 끝-스크롤 판정을 위해). 빈 헤더 표(서명란)는 헤더 행 생략, [별지] 서식은 모노스페이스 + 가로 스크롤
- `app/test/features/my/domain/contract_template_renderer_test.dart` — 신규. §A 전문 146블록 시그니처 골든(이미지 골든 아님 — 하우스 선례 0건) + 결정성 + 거부 규약 32테스트
- `app/test/features/my/presentation/widgets/contract_document_view_test.dart` — 신규. 360dp 오버플로 가드(Pretendard 실로드, P09 선례) 등 3테스트
- `app/test/support/contract_render_fixture.dart` — 신규. Vars 28종 + entityVars 픽스처(렌더러·뷰 테스트 공용)

**앱 시트 슬라이스 (2026-08-29)**

- `app/lib/core/api/dto/contract_dto.dart` — v2.18 `template_version`(기본 '')·`vars` 추가. vars는 방어 파서 `_contractVarsFromJson`(homework reps `_repsToString` 선례): 숫자 값 문자열화, map 아님 → 통째 빈 맵(부재와 같은 요약 경로), null 값 키는 버림("null" 인쇄 대신 MissingVars 정직 거부). codegen 재생성
- `app/lib/features/my/domain/my_models.dart` — ContractItem에 `firstSentAt`(체결일 미서명 폴백 :781)·`templateVersion`·`vars`·`hasDocumentSnapshot`(둘 다 있어야 렌더 자격 — 반쪽 스냅샷은 요약 경로) 추가
- `app/lib/features/my/data/my_repository_impl.dart` — 위 3필드 DTO→도메인 스레딩(first_sent_at은 종전에 DTO까지 받고 버려졌다)
- `app/lib/features/my/domain/contract_templates.dart` — 신규. 버전→번들 자산 표({"pt-v1"}), 미지 버전 null → §D ④ :916-917 업데이트 안내 폴백(모르는 버전을 손의 템플릿으로 렌더하지 않는다)
- `app/lib/features/my/presentation/contract_body.dart` — 신규. sealed 판정(None/Loading/Ready/NeedsAppUpdate/Unavailable) + `resolveContractBody`(스냅샷 유무 → 버전 표 → DefaultAssetBundle 로드 → 렌더). {{계약 체결일}}은 entityVars로만: SignedAt ?? FirstSentAt을 DateFmt.isoDate로 — 발송일·서명일 행과 같은 표기. 둘 다 없으면 키 자체를 안 넣어 MissingVars로 정직 폴백. **두 시트가 이 한 경로를 공용** — 판정이 갈리면 "서명 때 본 문서 ≠ 상세 재현 문서"(D-4)
- `app/lib/features/my/presentation/widgets/contract_sign_sheet.dart` — §D ⑤: 요약 위 전문 스크롤 영역(Flexible + 화면 45% 상한 — 작은 화면에서 서명 버튼을 밀어내지 않음), 시트가 ScrollController 소유, 끝-스크롤(ε=8px) 래치 후에만 체크박스 활성(잠긴 이유 한 줄 표시), 짧은 문서는 Ready 직후 postFrame 판정으로 자동 통과. 미지버전 배너·표시불가 정직 고지 시 게이트 안 닫음(P28 요약 고지 서명이 적법 기준선 — 요약·정산·약관 고지 전부 불변)
- `app/lib/features/my/presentation/widgets/contract_detail_sheet.dart` — §D ⑥⑦: Stateful 전환 + "계약서 본문" 보기/접기(기본 접힘, 읽기 전용 — 끝-스크롤 게이트 없음, [별지] 포함 재현). 레거시는 기존 PDF 문구 verbatim + 본문 행 자체가 안 생김. PDF 안내 줄은 스냅샷 있어도 유지(파일 부재는 여전히 참, §D ③)
- 테스트 신규 21: `test/core/api/dto/contract_dto_test.dart`(6 — 존재/부재/기형·null 값), `test/support/fake_asset_bundle.dart`(주입용), `test/features/my/presentation/widgets/contract_sign_gate_test.dart`(8 — 실자산 게이트·래치·짧은 문서·체결일 FirstSentAt·원천 충돌·미지버전·MissingVars·레거시 명시), `contract_detail_body_test.dart`(5 — 재현·SignedAt 우선·레거시 verbatim·미지버전·표시불가), `my_repository_failure_test.dart`(+2 스레딩)

**백엔드 + 문서 슬라이스 (2026-08-29)**

- `backend/internal/domain/contract.go` — Contract에 `TemplateVersion`(`template_version`)·`Vars`(`vars`) 추가. omitempty 없음(P37 리뷰 규약 — toDoc 통문서 Set 무손실, 주석으로 명문화). SHA256 주석을 봉인 의미로 갱신(pdf_path는 후속 자리 유지)
- `backend/internal/api/contract_template.go` — 신규. 템플릿 레지스트리(pt-v1 issuable=false + 요구 슬롯 22종, 키→출처 주석 표), gatherContractVars(스토어 읽기 — 트랜잭션 밖 전용), assembleContractVars(순수·전부-아니면-전무를 반환형으로 강제), 값 직렬화(납부일정·콤마 금액·위약금율 정밀도·결제방법 복수 병기·무제한/적용), canonical_json(JSON.stringify 호환 최소 이스케이프) + contractSeal. **api 레이어인 이유**: 요구 슬롯+래치는 발행 정책이고 조립은 5엔티티 조인 — 도메인 단일 엔티티 파일의 일이 아니다(buildContractForPass 선례)
- `backend/internal/api/service.go` — 계약 구역만: buildContractForPass(래치 ON 시 스탬프 시도 — 결제 2키 부재로 통상 스킵, 시점 현실 주석), SendContract(조립 pre-tx + mutate 안 재할당 스탬프 + 보존 규약), SignContract(Vars 있을 때만 같은 트랜잭션 봉인). CreateContract(수동 draft)는 무변경 — Vars는 send 의미론(§D ⑤)
- `backend/internal/api/contract_template_test.go` — 신규. 레지스트리 래치·22키 고정, canonical 골든/이스케이프/결정성(40회 재구성), 봉인 골든 벡터(python 독립 재도출 hex), 경계 테스트, 직렬화 유닛(납부일정 waived 결측 포함)
- `backend/internal/api/service_contract_stamp_test.go` — 신규. latch-off 불변 명시 단언, 발급 스킵(결측 사유 정확 일치) → 결제 후 재발송 22키 스탬프, 재확정 vs 위약금율 불변 대조, 불완전 재발송 보존, 서명 봉인/무봉인
- `docs/API계약_v1.md` — **v2.18** append(스키마·래치·스탬프 시점·스킵/보존 규약·직렬화 동결·봉인 공식·"sha256 비어 있음 ⟺ 요약 고지 서명"·클라이언트 additive 호환)
- `docs/계약서_PT이용계약_v1.md` — §C-3 헤더의 stale "코드에 없음"만 정정(기본 6칸은 v2.13 Business로 등록됨, 신규 3슬롯만 미결)

## 검증

**앱 렌더러 슬라이스 (2026-08-29)**

- `flutter analyze` 클린 / `flutter test` 전체 **1056개 전부 통과**(기존 1021 회귀 없음 + 신규 35)
- §A 자산 = 원문 diff 바이트 동일(가버전 헤더 제외), 고유 슬롯 29종 = §C 대조 일치
- 골든 시그니처(146블록)와 grep 전수 인벤토리(h1 1·h2 2·h3 25·표 7·펜스 2·수평선 3·인용 3·목록 17)가 독립 경로로 일치
- 뮤테이션 **5/5 kill** (되돌리면 실패 → 복구 확인): ① 슬롯 정규식 `{{`→`{{{` (-15) ② 비순서 목록 거부 분기 무력화 (-2) ③ 누락 키 수집 첫 키만 (-1) ④ 표 열 수 검증 무력화 (-1) ⑤ 슬롯 원천 충돌 검사 무력화 (-1)
- 자문자답 해소: 펜스 안 슬롯 치환 여부 — [별지] "받는 사람" 칸이 작동하는 서식이어야 해서(방판법 §30①6) **치환한다**로 확정 / CommonMark와 해석이 갈릴 인접 배치(세텍스트 `---`·지연 연속)는 미지 문법으로 **거부** / 치환은 파싱 뒤 — 값이 문서 구조를 흔들 수 없어야 D-4가 값 내용과 무관하게 성립

**백엔드 슬라이스 (2026-08-29)**

- `go build ./...` · `go vet ./...` · `go test ./...` 전부 통과(라이브 트리 — P41 동시 작업분 포함) + `go test -race ./internal/api/` 클린
- 에뮬레이터 컨포먼스(firebase emulators:exec, JDK 21): 계약 전이 포함 전부 통과. **유일 실패 1건 = Center 신원 서브테스트(CenterIdentityRoundTripAndCoexist)** — P41(v2.16) 소관의 기지 결함, 이 변경과 무관(외부 소견, 불간섭)
- 뮤테이션 **6/6 kill, 초기 생존 0** (각각 반전 → 실패 확인 → 복원): ① 발행 래치 반전(latch-off 불변 + ON 경로 5개가 사멸시킴) ② 전부-아니면-전무 제거 → 부분 스탬프(4개 테스트) ③ 보존 규약 제거(보존 테스트가 **유일 방어선**임 실증) ④ Vars 없어도 봉인(2개) ⑤ canonical 정렬 제거(골든+결정성 3개) ⑥ 재확정→최초 1회만(재확정 대조 테스트가 유일 방어선)
- 골든 순환 배제: canonical 문자열·sha256 hex를 python(json.dumps + hashlib)으로 **구현과 독립 재도출**해 박음
- 자문자답 해소: 결제 여러 건(카드+현금 분할 = 정상 영업, v2.4)의 {{결제방법}} — 영구 스탬프 불가 대신 canonical 순서 "·" 병기로 확정 / waived 회차 — 동결 포맷이 표현 못 하므로 결측(실무 도달 불가: 환불 패스 send는 트랜잭션 안 가드가 차단) / 0.1×100 부동소수점 잔여(10.000000000000002)가 계약서에 인쇄되지 않게 앱 시트와 같은 정밀도로 반올림 / **교차검증 관찰**: 서버 요구 22키 vs 템플릿 슬롯 29종 — 갭 7종(체결일=entityVars, 신규3+부가상품3=미결)은 발행 스위치 시점의 템플릿 최종 동결에서 정합(후속 작업에 기존재)

**앱 시트 슬라이스 (2026-08-29)**

- `flutter analyze` 클린 / `flutter test` 전체 **1082개 전부 통과** (착수 시점 라이브 트리 1061 + 신규 21, 기존 회귀 0 — 렌더러 슬라이스 기록 1056과의 차 5는 P40·P41 병행 작업분)
- 뮤테이션 **6/6 kill** (각각 변이 → 실패 확인 → 원복, 잔여물 grep 0): ① 끝-스크롤 게이트 조건 무력화(-2) ② 스크롤 리스너 제거(-2) ③ 미지 버전 → pt-v1 폴백 렌더(-2, 양 시트) ④ entityVars를 vars에 병합(-1, 원천 충돌 테스트가 유일 방어선) ⑤ entityVars 미배선(-4) ⑥ 체결일 SignedAt/FirstSentAt 우선순위 반전(-1)
- 자문자답 해소: rootBundle(CachingAssetBundle) 캐시 Future는 **다음 testWidgets의 FakeAsync 존에서 완료되지 않는다** — 임시 프로브 테스트로 실증(운영은 FakeAsync 없음·무영향). 테스트 규약: 실자산 로드는 파일당 첫 테스트 1회, 나머지는 테스트별 새 FakeAssetBundle(독립 캐시) / 짧은 문서 판정은 Ready 직후 postFrame(스크롤 이벤트가 영영 없는 경우) / 게이트는 래치 — 끝까지 읽고 되감아도 유지 / Loading 동안 게이트를 닫아 "열림→닫힘" 역행(체크 후 풀림) 방지 / 반쪽 스냅샷(버전만·vars만)은 hasDocumentSnapshot=false로 요약 경로(부재 우선)

(오케스트레이터 교차검증 대기)

## 후속 작업

- 발행 스위치(issuable=true)는 람 결정 2건 + §F 체크리스트 완료 후 — 그때 템플릿 최종 동결(pt-v1: 신고번호 행 유무·보증보험 문구·부가상품 조문 확정). **동결 시 함께**: 자산 최상단 h1 "§A 계약서 본문"(추출 흔적 헤딩 — 시트 슬라이스 발견, 회원에게 그대로 렌더됨) 정리 + 골든 재고정, 앱 슬롯 29종 vs 서버 요구 22키 갭 7종 정합.
- 어드민 본문 열람 화면(§D에 설계 없음 — 별도 설계 후)
- 프로덕션 스탬프 개시 후 운영 확인 1회: 결제 기록 → 재발송 → 앱 전문 렌더 → 서명 → sha256 봉인의 실기기 E2E(래치 ON 전에는 불가능한 검증).
- status 완료 기준: 기계 축(코드)은 완비 — 발행 스위치·동결은 별개 작업이라 이 P는 닫는다.

## 참조

- 설계 원본: docs/계약서_PT이용계약_v1.md §C(슬롯 29종)·§D(렌더링)·§F(발행 체크리스트), [P28](P28-pt-contract-draft.md)
- 착수 판정: 2026-08-29 읽기 전용 분석(PARTIAL — 기계 축 BUILDABLE-NOW, 동결·3필드·게이트만 대기), [P36](P36-admin-contract-audit.md) H(열람 불가)·기지 갭(sha256 0곳)
- 토대: [P37](P37-contract-transition-atomicity.md) TransitionContract(봉인이 얹힐 트랜잭션), [P27](P27-center-business-info.md) Business 12칸
