---
id: P44
title: 전자서명 완성 — 서명 입력·서명란 반영·체결 증명 (법령·관행 리서치 기반)
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P44 — 전자서명 완성 (서명 입력 · 서명란 반영 · 체결 증명)

## 목표

람 질문 3개에 최신 1차 출처로 답하고 그 결론대로 구현한다: ① 지금 구조(스크롤 게이트+동의 탭+서명일시·IP·sha256)에서 서명하면 서명란에 뭐가 들어가나 — 현재는 아무것도 안 들어간다(`{{회원명}} (서명)` 리터럴) ② 그게 법적 효력이 있나 ③ 자필 사인 입력 칸이 필요한가, 업계는 어떻게 하나. **기억 의존 금지** — 전자서명법·전자문서법·방판법 현행(2026-08 기준)과 국내 전자계약 서비스 관행을 리서치로 확정 후 설계.

## 결정 사항

(리서치 3트랙 교차검증 후 확정 — 근거는 검증 절의 리서치 요약 참조)

1. **자필 서명 패드 채택, 그리기 단일** — 법적 요건이 아니라(§2-2 기술중립 정의 + 판례 심사축은 본인확인·의사표시·무결성) **관행·체감·증거 보강** 목적임을 구분해 기록. 인앱·현장 계약(보험 전자청약·헬스장 태블릿)에서 자필 패드가 사실상 표준. 타이핑 생성(자동 필기체)은 기각 — 한글 필기체 폰트 자산·라이선스 비용 대비 이득 없음(그리기는 어떤 표식이든 유효 — 효력의 뿌리는 휴대폰 인증 계정+동의 행위). 이미지로만 보관(특징점 추출 없음) → 생체인식 민감정보 비해당 구조(PIPC 2024.12 안내서 기준 체계 — 명문 아님을 병기).
2. **저장 = 계약 문서 내 base64 2필드**(signature_png·signature_sha256, omitempty 금지) — 실측 5~18KB(문서 한도 1~4%), 5년 보존·탈퇴 비파기(P22 계약 비접촉)를 저장 위치만으로 자동 상속. Storage 파일안 기각(규칙·수명주기·오프라인 열람 3중 비용).
3. **봉인 분리 = Dropbox 2해시 모델과 동형** — sha256(내용: 버전+vars, send 확정물)은 불변, 서명 이미지는 같은 트랜잭션의 **별도 해시**. 이미지를 vars에 넣지 않는다(직렬화 명세 동결 + send 시점에 존재하지 않음). 체결 정보 표시가 두 해시의 역할을 명시해 "봉인된 것처럼 보이는 비봉인 요소" 문제를 정직하게 해소.
4. **문서 표시 = 서명란 표 직하단 도킹 블록**(뷰 레이어만) — 렌더러·모델·템플릿 무변경(이미지 문법 거부 규약 유지). 서명 이미지 + "회원 서명" 라벨 + 서명 일시. 센터 측은 "(인)" 텍스트 유지 — 사전 날인 직인 이미지는 업로드 인프라 필요라 후속(관행상 표준임은 기록).
5. **시트 2단 전환** — 1단(전문 스크롤 게이트+요약 고지+동의 체크) → "서명하기" → 2단(패드 + 다시 쓰기 + 미리보기, 문서는 접힘 — 높이 경합 해소, enableDrag 끔). 최종 버튼 문구 "동의하고 서명합니다"(모두싸인 표준 패턴). 빈 서명 방지: 최소 획 1 + 바운딩 박스 하한(관대하게).
6. **구버전 호환 = 바디 없는 sign 계속 유효** — signature 빈 값 ⟺ 체크 동의만(sha256 빈 값 신호와 동형). 서버는 요청 바디를 옵션으로 받고 검증(base64·PNG 매직·크기 상한)만 강제.
7. **체결 정보 섹션**(상세 시트, signed 전용) — 업계 감사추적인증서 코어 필드 중 실보유분: 서명 일시·본인인증 수단(휴대폰 본인인증 계정)·서명 IP·문서 해시·서명 해시·템플릿 버전·최초 발송일. **법정 추정력 주장 금지** — 현행법상 어떤 전자서명에도 추정 조항 없음(공인전자문서센터 §31조의7만 예외), 우리 해시는 입증 수단이라는 사실 그대로.
8. **제18조② 문구 갱신**(래치 OFF 창 — 버전 범프 없이): 기록 항목 열거에 서명 이미지 추가. privacy.html 초안의 수집 항목도 정합(오케스트레이터 직접).
9. 이월: 열람 완료 이벤트의 서버 기록(현 스크롤 게이트는 클라이언트 강제 — 증거로는 서명 행위에 흡수), 별지 감사추적인증서 PDF(pdf_path는 §D ③대로 계속 빈 자리), 센터 직인 이미지, 위변조 자가 검증 UI.

## 진행 단계

- [x] 리서치 3방향 병렬(2026-08-29) — 법령: 전자서명법 §2·§3, 전자문서법 §4·§4의2·§7·§31조의7, 방판법 §7·§30 **원문 확인**(law.go.kr 조문 팝업) + 대법 2023다294180(2025-08-14)·2017다257395 + PIPC 생체정보 기준 + 전상법 5년 / 업계: 국내 5·글로벌 3 서비스(그리기 강제 없음·인앱 현장은 자필 패드 표준·감사추적인증서 코어 필드) / 코드: 12단계 흐름 맵·저장 2안 실측·봉인 경계 판정
- [x] 교차검증 + 자문자답 → 결정 사항 9개 확정(모순 0: 법 "필수 아님" × 관행 "표준임" × 코드 "안전 가능")
- [x] 구현 (백엔드·앱·템플릿) + 오케스트레이터: privacy.html 수집 항목·이용 목적 서명 이미지 명시, 계약서doc 마스터 제18조② 동기화
  - [x] 백엔드: sign 옵션 바디 + signature_png·signature_sha256 저장 + 검증 게이트 + 계약 v2.21 (2026-08-29)
  - [x] 앱: 서명 패드(그리기 단일·정규화 저장·PNG 내보내기) + 시트 2단 전환 + 체결 완료 단계 + 서명란 도킹 블록 + 체결 정보 섹션 + DTO/모델/스레딩 (2026-08-29)
  - [x] 템플릿: 제18조② 기록 항목에 서명 이미지 추가 — 두 변형 동일 문장, 가버전 창이라 버전 범프 없음 (2026-08-29)
- [x] 검증 + 마감
  - [x] 백엔드: build/vet/test(-count=1)/-race(api) 그린 · 뮤테이션 5/5 격추 · Firestore 인덱스 예외 불요 문서 검증
  - [x] 앱: flutter analyze 무결 · 전체 스위트 1,131개 그린(기준선 1,097 + 신규/확장 34) · 뮤테이션 9/9 격추 · 내보내기 실측 4.1KB(2획, 680×360)
  - [x] 오케스트레이터 교차검증(2026-08-29): 3계층 직접 재실행 그린 + 봉인 호출부(`contractSeal(버전, vars)`) 바이트 불변 정독 + **실서버 E2E** — 데모 서버에 실제 PNG POST → signed·서명 해시 독립 재계산 일치·**내용 해시가 서명 유무와 무관하게 동일**(717ab3e8… 재현 — 2해시 분리 실증). ⚠ 최초 E2E는 signature 키 부재 오탐 — 원인은 P43 시절 **좀비 서버**(`go run` 배경 실행을 kill %로 죽이면 자식 바이너리가 포트 생존)가 curl을 받은 것. PID 종료 + `go build` 바이너리로 재검증 통과. 교훈: 이후 로컬 E2E는 빌드 바이너리 + PID 종료로

## 변경 파일

### 백엔드 (2026-08-29)

- `backend/internal/domain/contract.go` — Contract += `signature_png`·`signature_sha256` (omitempty 금지 규약 유지, 2해시 분리·법정 추정 아님 주석)
- `backend/internal/api/handlers_contracts.go` — sign 옵션 바디(바디 없음=구버전 유효) + `decodeSignaturePNG` 검증 게이트(base64→PNG 매직→64KB→치수 50~2000×20~2000) + 인덱스 판정 주석
- `backend/internal/api/service.go` — `SignContract`에 `signaturePNG []byte` 파라미터. 해시(원본 바이트)·정규 base64는 트랜잭션 밖 캡처, mutate 안 조건 재할당. `contractSeal` 호출부는 바이트 불변
- `backend/internal/api/service_contract_sign_test.go` — 신규: 쌍 골든(2해시 분리)·잔존 비클로버·와이어(구버전 3표기/서명 첨부/400 테이블 7종)
- `backend/internal/api/service_contract_test.go` — `TestRefundKeepsSignedContract` 확장(서명 이미지 환불 생존) + SignContract 시그니처 배선
- `backend/internal/api/service_account_test.go` — P40 탈퇴 스위트 signed 픽스처에 서명 이미지 비파기 확장
- `backend/internal/api/service_contract_stamp_test.go`·`service_test.go` — SignContract 시그니처 배선(nil)
- `backend/internal/store/conformance_test.go` — `testContractTransitionFresh`에 2필드 통문서 왕복·롤백 보호 스팟체크
- `docs/API계약_v1.md` — **v2.21** 섹션(와이어·검증 400·빈 값 신호·2해시 역할·저장 위치 근거·인덱스 판정)

### 앱 (2026-08-29)

- `app/lib/features/my/presentation/widgets/signature_pad.dart` — 신규: 패드 위젯 + 컨트롤러(GestureDetector+CustomPainter, P32 계보). 획은 패드 크기 비율(0~1) 정규화 저장(회전 유실 함정 차단), 유효성 = 획≥1 + bbox ≥ 패드 폭 15%(결정 5 관대 하한), 내보내기 = PictureRecorder→투명 PNG(dpr 상한 2x, 40KB 초과 시 0.7배 재렌더 ≤3회, 바닥 320×140px)
- `app/lib/features/my/presentation/widgets/contract_sign_sheet.dart` — 2단 전환(결정 5): 1단 오늘 그대로+버튼 의미만 변경 → 2단 확인 라인·전자 교부 고지(결정 8 연장)·패드·"동의하고 서명합니다" → 체결 완료 단계(썸네일+[계약서 보기]/[닫기]). 라우트 enableDrag=false(생성 시점 고정이라 단계 토글 불가 — 시트 전체 OFF). 레거시/미지 버전/표시 불가 경로도 같은 2단 패드
- `app/lib/features/my/presentation/widgets/contract_detail_sheet.dart` — 서명란 도킹 블록(결정 4: 마지막 표 직하단, 이미지+회원 서명+서명일) + 체결 정보 섹션(결정 7: 실보유분만, 정직 캡션, 레거시는 일시·IP만) + 패턴 B 전체 스크롤 전환(체결 정보 7행이 SE 높이 예산 초과)
- `app/lib/features/my/presentation/widgets/contract_document_view.dart` — 옵션 `signatureBlock` 파라미터(뷰 레이어만, 기본 null=0 변화, 마지막 ContractTable 뒤 도킹·표 없으면 끝)
- `app/lib/features/my/presentation/my_screen.dart` — showContractSignSheet에 onViewSigned 콜백 배선(시트 닫힌 뒤 화면 context로 상세 열기)
- `app/lib/core/api/dto/contract_dto.dart` — signature_png·signature_sha256 (+ freezed/json 재생성; signer_ip·sha256은 기왕 존재)
- `app/lib/features/my/domain/my_models.dart` — ContractItem += signerIp·sha256·signaturePng·signatureSha256·hasSignatureImage
- `app/lib/features/my/domain/my_repository.dart` · `data/my_repository_impl.dart` · `data/my_remote_data_source.dart` · `presentation/my_view_model.dart` — signContract에 옵션 signaturePng 스레딩(null=바디 없음, 결정 6) + DTO→모델 매핑(빈 IP·해시는 null 접기)
- `app/assets/legal/contract_pt_v1_reported.md` · `contract_pt_v1_exempt.md` — 제18조② 갱신(두 변형 동일 문장, 결정 8)
- 테스트: `signature_pad_test.dart`(신규 8) · `contract_sign_flow_test.dart`(신규 9) · `my_remote_data_source_sign_test.dart`(신규 2) · `contract_document_view_test.dart`(+3) · `contract_detail_body_test.dart`(+3, 재고정 1) · `contract_detail_test.dart`(+3) · `contract_dto_test.dart`(+3) · `my_repository_failure_test.dart`(+2) · `contract_template_renderer_test.dart`(+1) · 기존 fake 6곳 시그니처 배선

## 검증

### 백엔드 (2026-08-29)

- `go build` / `go vet ./...` / `go test -count=1 ./...` 전부 그린, `-race`(api) 그린
- 뮤테이션 5/5 격추(초기 생존자 0): ① 매직 검사 제거 — JPEG 케이스 문구 분리("PNG 형식" vs "해석할 수 없어요")로 검출 ② 크기 상한 제거 — IEND 뒤 패딩 픽스처가 200 통과해 즉사 ③ 서명→contractSeal 주입 — 쌍 골든+명시적 쌍 대조 발화 ④ 무-서명 항상 재할당 — 잔존값 비클로버 테스트 발화 ⑤ base64 문자열 해시 — 정의 기반 독립 재계산 2곳 발화
- Firestore 인덱스(기억 의존 금지 — 1차 출처 교차검증): quotas "Field values over 1500 bytes are **truncated**"(쓰기 성공, 인덱스 엔트리만 절단) — firebase.google.com/docs/firestore/quotas · docs.cloud.google.com/firestore/native/docs/quotas 동일 문구. **예외 불요 판정**, firebase.json·firestore.indexes.json 무변경. 예외는 저장비용 절감 권고(best-practices)로만 존재 → 후속 기록
- 자문자답 해소: 바디 없음/`{}`/`""`/null 전부 구버전 경로(400 아님) · data URI는 base64 400 · 미지 필드 400(strictUnmarshal) · 1MiB 바디 상한은 decodeJSON과 동일 적용 · conformance에 계약 필드 고정 roundtrip이 원래 없어 TransitionContract 서브테스트에 스팟체크로 신설

### 앱 (2026-08-29)

- `flutter analyze` 무결 · **전체 스위트 1,131개 그린**(작업 전 기준선 1,097개 → +34)
- 뮤테이션 9/9 격추: ① bbox 하한 0 → 점 무효 테스트 발화 ② bbox 조건 제거 → 동일 ③ 1단 동의 게이트 제거 → 잠김 테스트 발화 ④ 최종 버튼 패드 게이트 제거 → 빈 패드 잠김 발화 ⑤ 도킹 위치 문서 끝 → 배치 테스트 2파일 발화 ⑥ hasSignatureImage 상시 true → 레거시 3건 발화 ⑦ 체결 정보 signed 게이트 제거 → sent 부재 발화 ⑧ enableDrag true → 플로우 7건 발화(시트가 실제로 획을 훔침 — 경합 실존 역증) ⑨ 데이터소스 바디 탈락 → wire 테스트 발화
- 내보내기 실측: 2획 서명 680×360px(2x) = **4,121 bytes** — 결정 2의 5~18KB 창 하단보다도 작음, 서버 상한(64KB)·치수 게이트(50~2000×20~2000) 여유 통과. 노이즈 프로브: 400획 7.8KB·1,600획 2.3KB → 40KB 상한은 도달 불가한 방어 레일(균일 잉크 + PNG 압축), 축소 루프는 테스트 시임(maxBytes)으로 결정적 검증
- 골든 재고정 1건(의식적): contract_detail_body_test `{{계약 체결일}}` 테스트의 광역 `'2026-08-20' 부재` 단언 → `'체결일: 2026-08-20' 부재`로 축소 — 체결 정보의 정당한 "최초 발송일" 행과 충돌, 원 의도(문서 체결일이 발송일로 렌더 금지)는 그대로. 렌더러 골든(143블록 시그니처·개수)은 무변경 — 제18조②는 문단 텍스트 변경이라 구조 불변, 새 내용 단언 1건 추가
- 자문자답 해소: 시트 enableDrag는 라우트 생성 파라미터라 단계별 토글 불가 → 시트 전체 OFF(결정 5 문구 그대로, 스크림 탭·백 제스처 닫힘 유지) · 내보내기 실패 시 바디 없이 제출(결정 6 — PNG 인코딩 실패가 적법 서명을 좌초시키지 않음, 썸네일만 생략) · 상세 시트는 패턴 B 전환으로 SE(667dp) 오버플로 예방(본문 ConstrainedBox 상한 유지, Flexible은 스크롤 안에서 불가라 제거) · 깨진 base64/비PNG 데이터는 블록 생략(가짜도 오류 상자도 아닌 "없음")

## 후속 작업

- (앱) 체결 완료 [계약서 보기]의 재조회 실패 폴백은 서명 전 스냅샷으로 열림(이미지 없이) — 오프라인 직후 열람 시 한정, 재진입하면 정상. 로컬 바이트로 즉석 합성하는 대안은 "서버 기록 = 표시" 원칙과 상충해 기각
- (앱) 서명 일시·서명일·최초 발송일은 KST 벽시계 표기 — 기존 상세 메타의 발송일/서명일 행(P22, 원시 파싱값 표기)과 자정 부근 ±1일 갈릴 수 있음. P44 범위 밖이라 미수정, 통일은 후속
- (결정 9 이월) 열람 완료 이벤트 서버 기록 · 별지 감사추적인증서 PDF · 위변조 자가 검증 UI · 센터 직인 이미지(사전 날인 관행)
- (리서치 잔여) 특수판매 소비자보호 지침 예규 제493호(2025.12 개정) 원문의 전자 교부 조항 존재 여부 — 접근 실패로 미확인, 확인되면 반영
- (UX 수용) 서명 시트 enableDrag 전체 OFF로 1단 스와이프-닫기 상실(스크림 탭·백 제스처 유지) — 라우트 파라미터 제약, 불만 시 재검토
- 실기기 확인 1회 권장: DEV_SEED 서버 + 앱 member1 → 모빌리티 계약 → 전문 스크롤 → 서명하기 → 패드 → 동의하고 서명합니다 → 체결 완료 → 상세 서명란·체결 정보

## 참조

- 현행 구현: [P39](P39-contract-document-machinery.md)(스크롤 게이트·sha256 봉인) · [P42](P42-contract-template-variants.md)(변형 2종) · 계약서doc 제18조(전자계약 조항 — 클릭 동의 방식 기왕 규정)
