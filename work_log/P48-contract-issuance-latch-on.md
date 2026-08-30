---
id: P48
title: 발행 래치 ON — 계약서 발행 스위치를 올린다
status: 완료
domain: backend
created: 2026-08-30
completed: 2026-08-30
---

# P48 — 발행 래치 ON (issuable: false → true)

## 목표

대표(센터 대표) 명시 지시로 계약서 템플릿 레지스트리의 발행 래치를 켠다. P39 결정 1이 세워 둔
`issuable` 게이트는 "람 결정 2건(체육시설업 신고·사업자 등록) + 계약서doc §F 체크리스트 뒤"를
조건으로 걸어 뒀고, 그 결정이 내려졌다. `contractTemplates`의 두 변형(`pt-v1-reported`·
`pt-v1-exempt`)을 `issuable: true`로 올리고, 이 뒤집힘이 만드는 **테스트·문서의 진실 변화**를
조용히 흘리지 않고 전부 따라 고치는 것까지가 이 작업의 범위다.

핵심 긴장: 래치를 켜도 **오늘 관측 가능한 동작은 하나도 안 바뀐다**(프로덕션 Firestore에
Business 미등록 + `facility` 절 부재 → unknown). 이걸 "그러니 안전한 무해 변경"으로 적으면
거짓말이고, "이제 계약서가 발행된다"로 적어도 거짓말이다. 정확한 표현은 **잠금 해제**다 —
남은 잠금이 코드·배포가 아니라 대표의 데이터 입력 2건뿐인 상태가 됐다.

## 결정 사항

- **`issuable` 필드·`contractSkipLatchOff` 사유·`EnableContractTemplatesForDemo` 훅 전부 존치.**
  래치가 켜졌다고 스위치를 뜯으면 되돌림이 배포 롤백이 된다. 되돌림은 한 줄이어야 한다.
  데모 훅은 사실상 no-op이 됐지만 남긴다 — ① 래치를 되돌려도 데모 경로는 켜진 채여야 하고
  (데모의 정직함이 프로덕션 스위치에 인질로 잡히지 않는다) ② 그 훅을 부르는 테스트가 **호출
  전에** 레지스트리 리터럴을 단언해 뮤테이션 고정점 역할을 계속한다.
- **latch-off 테스트는 삭제가 아니라 픽스처화.** "래치가 꺼져 있으면 스탬프도 없고 facility
  읽기조차 없다"는 진짜 보장이다 — 롤백 스위치가 실제로 종전 경로를 복원하는지 아무도 증명하지
  않으면 롤백은 희망사항이 된다. 기존 `withIssuableContractVariants`의 거울로
  `withLatchOffContractVariants`(t.Cleanup 원복)를 만들어 **보장을 옮겼다**.
- **레지스트리 상태 단언은 방향만 뒤집고 유지.** P43이 심어 둔 "프로덕션 리터럴이 issuable=true면
  실패"는 이제 의도적으로 반대가 됐다. 단언의 값어치는 방향이 아니라 *리터럴이 조용히 표류하지
  않는다*는 데 있으므로, 지우지 않고 "false면 실패"로 재목적화했다 — 실수로 되돌려 **발행이
  조용히 멈추는 사고**를 이제 이 단언이 잡는다.
- **문서는 정정을 명시.** API계약 문서의 규약이 "모든 섹션이 계약의 일부"라, v2.18의 "발행
  래치는 꺼진 채 배포된다"를 조용히 반박하지 않고 v2.22 본문에 **대체 선언**을 박았다.
- **service.go는 건드리지 않았다**(병렬 세션 영역). 그쪽 게이트 주석은 조건부 서술이라 여전히
  참이지만 "래치 OFF" 문구가 배포 상태로 오독될 여지가 있다 — 후속으로 남긴다.

## 진행 단계

- [x] 레지스트리 플립 + 주변 주석 전면 재작성(세 게이트 구조·잠금 해제의 의미·데모 훅 존치 사유·
      첫 서명 전/후 템플릿 동결 경계)
- [x] 깨질 테스트 식별 → 4건 의식적 갱신(아래 "변경 파일") + latch-off 픽스처 신설 + latch-off
      전용 순수함수 테스트 신규 1건
- [x] 전면 검증: build · vet · `go test -count=1 ./...` · `-race`(internal/api) · Firestore
      에뮬레이터 적합성 스위트
- [x] 뮤테이션 패스: `pt-v1-reported`만 false로 되돌림 → 3개 테스트 발화 확인 → 원복 후 재검증
- [x] 문서: `docs/API계약_v1.md` v2.22 신설(정정 선언 포함) · `backend/README.md` 래치 문단 갱신

## 변경 파일

- `backend/internal/api/contract_template.go` — **레지스트리 플립**(:186–187 `issuable: true` ×2).
  주석 재작성 4곳: 파일 헤더(:3–4 — v2.18 → v2.19 → **v2.22** 계보), `issuable` 필드(:69–78 —
  존치 사유 = 되돌림 한 줄), `contractTemplates` 위 **발행 래치 ON 블록**(:162–184 — 세 게이트 표,
  "관측 변화 0이지만 안전장치가 아니라 잠금 해제", 첫 서명 전 교체 자유/후 동결),
  `EnableContractTemplatesForDemo`(:190–199 — no-op이 된 사실 + 존치 2사유).
  `contractSkipLatchOff`(:215–217)·`contractStampLatchOn`(:221–228)·`contractTemplateForStatus`
  (:242–243)에 "P48 이후 프로덕션에선 이 갈래가 안 나온다" 주석.
- `backend/internal/api/service_contract_stamp_test.go` — **`withLatchOffContractVariants` 신설**
  (:56–79 — 프로덕션 엔트리를 제자리에서 OFF로 뒤집고 t.Cleanup 원복 + "픽스처가 무력하면 즉시
  Fatal" 자기검증). 파일 헤더 축① 서술 갱신("배포 진실" → "되돌림 구성의 보장").
  픽스처 적용 3건: `TestContractLatchOffStampsNothing` · `TestContractLatchOffNeverStampsAnyStatus`
  (서브테스트마다) · `TestContractLatchOffReadsNoFacility`(GetFacility 호출 0회 단언 — 이 테스트가
  없으면 롤백 시 "스탬프는 안 하는데 읽기는 하는" 절반짜리 복귀를 아무도 못 본다).
- `backend/internal/api/contract_template_test.go` — `TestContractVariantRegistryLatchOffAndKeys`
  → **`TestContractVariantRegistryIssuableAndKeys`**(단언 반전: `!tpl.issuable`이면 실패,
  `contractStampLatchOn()`이 **참**이어야 함). `TestContractTemplateForStatusSkipReasons` —
  reported/exempt가 이제 스킵 없이 각 변형을 고르는 것으로 갱신(+ 요구 슬롯 비지 않음 단언),
  unknown 스킵은 그대로. **신규 `TestContractTemplateForStatusLatchOffSkips`** — 래치 OFF 구성에서
  상태 선택이 래치를 대체하지 않고 합성된다는 P42 규약 + 게이트 순서(상태 → 래치) 역전 감시.
- `backend/internal/api/service_demo_seed_test.go` — P43 사전 단언(:30–47) **재목적화**: "전부 OFF"
  → "두 변형 모두 ON", 이유를 주석에 명시(방향이 아니라 표류 감시가 값어치). 데모 훅 Cleanup 규율은
  그대로 유지.
- `docs/API계약_v1.md` — **v2.22 신설**(:2293–). v2.18/v2.19의 래치 OFF 문장을 명시적으로 대체
  선언 + 무엇이 바뀌었나(와이어 불변·스토어 접근 1회 증가) + 지금 막고 있는 두 게이트의 실제
  프로덕션 상태 + 대표가 할 일 2건과 그 순간 벌어지는 일 + 첫 서명 = 템플릿 동결 경계 + 데모 훅
  + 배포 순서(앱 자산 선행 확인 권고).
- `backend/README.md` — 계약 스냅샷 문단(:447–) 갱신: "발행 래치 뒤에 완비" → "래치는 이제 켜져
  있다", v2.18 문장이 더 이상 사실이 아님 명시, 남은 두 게이트와 잠금 해제의 의미, facility 추가
  읽기 1회, 첫 서명 전까지만 교체 자유.

## 검증

- `go build ./...` · `go vet ./...` 무출력. `go test -count=1 ./...` **전건 그린**(api / config /
  domain / store). `go test -race -count=1 ./internal/api/` **그린**(2.3s).
- Firestore 에뮬레이터 적합성 스위트 **그린** — `firebase emulators:exec --only firestore
  --project demo-rize --config testdata/firebase.json 'go test -tags firestore_emulator -count=1
  ./internal/store/'` → `ok ... 16.054s`, 스크립트 종료 코드 0(JDK 21 = zulu-21).
- **뮤테이션**: `pt-v1-reported`만 `issuable: false`로 되돌림 → **3건 발화** ①
  `TestContractVariantRegistryIssuableAndKeys`(재목적화한 레지스트리 상태 단언 — 의도한 킬)
  ② `TestContractTemplateForStatusSkipReasons`(latch_off 스킵으로 퇴행) ③
  `TestDemoSeedStampsSentContracts`(P43 사전 단언). 원복 후 재검증 그린.
- gofmt: 신규·수정 코드 전부 clean. `service_demo_seed_test.go`의 한글 열 정렬 1블록은 **P48
  이전부터 있던 것**(내가 손대지 않은 라인) — 프로젝트가 손정렬을 허용하는 자리라 원복하지 않았다.

## 후속 작업

- **대표 입력 2건이 곧 발행 개시 스위치다**: 어드민에서 ① 사업자 정보 6칸 등록 ② 시설 신고 상태
  선언(reported면 신고번호 필수). 그 순간부터 다음 발급·재발송이 실제로 스탬프한다 — 입력 **전에**
  앱 템플릿 자산 2종이 실기기에 나가 있는지 확인할 것(없으면 vars는 찍히는데 화면은 요약 고지 폴백).
- 첫 서명이 들어오는 순간 `pt-v1-reported`/`pt-v1-exempt`는 **동결**된다. 문구·슬롯 손질은 그
  전에 끝내야 한다(P47 템플릿 동결 준비와 같은 창).
- ~~주석 현행화 5곳~~ → **오케스트레이터가 즉시 처리**(2026-08-30): 거짓이 된 고지를 후속으로
  미루지 않는다는 코드베이스 자체 규약("고지와 실제가 갈리면 거짓 고지") 적용.
  ① `cmd/server/main.go` — "프로덕션 래치 OFF 보장" 결론 문장 삭제, 데모 훅이 **no-op이 된 사실 +
  존치 이유**(래치를 되돌리는 날 데모가 조용히 요약 고지로 후퇴하지 않게)로 재서술
  ② `service.go` 발급 스탬프 주석 — "래치 OFF면"을 "래치를 **되돌리면**"으로(롤백 구성 픽스처가
  고정하는 불변임을 명시, 배포 상태는 v2.22부터 ON)
  ③ `service.go` 보존 규약 주석 — nil 사유에 "시설 미선언·조립 불완전"을 앞세우고 래치는 괄호로
  ④ 앱 `contract_body.dart`·⑤ `contract_dto.dart` — 스냅샷 없음의 실제 사유(시설 미선언·사업자
  정보 미등록)로 교체, `contract_templates.dart`는 "폐기 **시점까지**"로 시제만 정정.
  검증: 백엔드 build·vet·전건 그린 / 앱 analyze 무결·전체 1,137 그린(다른 세션의 체형사진 RED 2건은
  그쪽 중간 상태였고 수리 확인) / 래치 ON 빌드로 발급→스탬프→서명→2해시 E2E 재실측.
- 래치 ON으로 발급·발송당 Firestore 센터 문서 읽기가 1회 늘었다. 지금 규모에서 무의미하지만,
  발행이 실제로 시작된 뒤 읽기 비용을 한 번 관측해 둘 것.

## 참조

- `docs/API계약_v1.md` v2.18(스냅샷 기계) · v2.19(변형 2종·게이트 합성) · **v2.22(래치 ON)**
- work_log: P39(계약 문서 기계·결정 1 래치) · P42(변형 2종) · P43(데모 경로·사전 단언 원본) ·
  P45(계약 축 마감 스윕 — 래치 OFF 배포를 SHIP 근거로 확인했던 리뷰) · P47(템플릿 동결 준비)
- `docs/계약서_PT이용계약_v1.md` §D ①(버전 고정)·§F(발행 전 체크리스트)·:818(신고 행 갈래)·
  제20조③(보증보험 결측 표기)·제23조②(약관 게시)
