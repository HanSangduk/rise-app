---
id: P20
title: 인바디 결과지 사진 → OCR 프리필 (온디바이스)
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P20 — 인바디 결과지 OCR 프리필

## 목표

수기 입력(P18)은 그대로 두고, 그 위에 "사진에서 채우기"를 얹는다: 카메라/갤러리 →
**기기 안에서** 글자 인식(ML Kit, 한국어) → 6지표+측정일 프리필 → 회원 확인 → 저장.
서버 비용 0, 결과지 사진은 저장·전송하지 않는다(이름·나이·성별이 함께 인쇄된 원본이다).

람이 실물 결과지 5장을 제공하면서 OCR의 v2 착수 게이트(③ 실물 실측)가 풀렸고,
직접 요청("사진 받아서 글자 인식해서 알아서 넣는 방식")으로 착수가 확정됐다.

## 결정 사항

- **자동 저장은 하지 않는다** — 실측에서 오인식이 실제로 났다(135.2, 적정체중, 제지방량).
  확신 없는 값은 채우지 않고 **빈칸**으로 둔다: 틀린 프리필은 회원이 그대로 저장하지만
  빈칸은 결과지를 보고 채운다.
- 파싱 규칙 R1~R11은 `design/inbody-ocr/parse.py` 헤더가 사양서다. 5장 실측
  **정확 30 · 빈칸 1 · 오답 0** (채울 수 있는 31칸). 함정 표는 `design/inbody-ocr/README.md`.
- 검증 게이트(범위·교차·항등)는 서버 v2.9와 같은 식 — 앱 `inbody_input_rules.dart`와 공유.

## 진행 단계

- [x] 0. 실물 5장 확보 → macOS Vision 하네스로 실측·정련 (스코어러 포함, 오답 0 달성)
- [x] 1. 이식 사양·함정 표를 `design/inbody-ocr/`에 고정, 실기기 갤러리에 5장 배치
- [x] 2. 앱 통합: `google_mlkit_text_recognition` 0.17.1(한국어) + `image_picker` 1.2.3
       (둘 다 2026-08-23 pub.dev API로 최신 stable 확인) → R1~R11 Dart 이식
       (`inbody_sheet_parser.dart`, 순수 도메인) → `inbody_add_sheet`에 "사진에서 채우기"
       (성공/부분/0건/실패 = 전부 같은 폼 — 수기 입력이 곧 실패 경로. Android 전용,
       iOS는 버튼 숨김 — 아래 후속 작업). 검증 섹션에 상세.
- [x] 3. 실기기 재실측(갤럭시 S21 · ML Kit 한국어 · 운영 서버) — 아래 결과
- [x] 4. 문서 마감 (계약 변경 없음 — 클라이언트 전용 기능)

## 변경 파일

- `design/inbody-ocr/{README.md, parse.py, ocr.swift}` — 신규(사양·프로토타입)
- 앱 통합(단계 2, 2026-08-23):
  - `app/pubspec.yaml` — google_mlkit_text_recognition ^0.17.1 · image_picker ^1.2.3 추가
  - `app/lib/features/records/domain/inbody_sheet_parser.dart` — 신규. R1~R11 이식
    (순수 도메인, Flutter/ML Kit 의존 0. R11의 범위·교차·항등은 `inbody_input_rules.dart`
    재사용 — 중복 정의 없음)
  - `app/lib/features/records/data/inbody_sheet_reader.dart`(+`.g.dart`) — 신규.
    image_picker + ML Kit(한국어) + 좌표계 어댑터(픽셀·y아래 → 정규화·y위) + 캐시 사본 삭제
  - `app/lib/features/records/presentation/widgets/inbody_add_sheet.dart` — "사진에서
    채우기" 버튼·프리필 표식("사진")·안내문 갱신("아직 없어요"는 iOS에만 잔존 — 사실 유지)
  - `app/test/features/records/domain/inbody_sheet_parser_test.dart` — 신규(17건)
  - `app/test/features/records/domain/fixtures/inbody/*.tsv` — 함정 표 합성 픽스처 15장
  - `app/test/features/records/data/inbody_sheet_reader_test.dart` — 신규(6건)
  - `app/test/features/records/presentation/widgets/inbody_photo_prefill_test.dart` — 신규(13건)
  - `app/test/features/records/presentation/widgets/inbody_add_sheet_test.dart` — 과장 금지
    테스트 갱신(문구가 기능 존재를 따라감)

## 검증

- 프로토타입: 5장 × 7칸 실측 표는 design/inbody-ocr/README.md 참조. 핵심 속성 = 오답 0.
- **참조 구현 대조(단계 2)**: 함정 표 각 행을 합성 토큰 TSV 15장으로 만들어
  parse.py(참조)와 Dart 파서에 **같은 입력**을 넣고 같은 출력 확인(생성·대조·뮤테이션
  하네스는 픽스처 옆에 보존: `app/test/.../fixtures/inbody/{gen_fixtures,mutate}.py`).
  적정체중(R1)·히스토리 열(R2/R2b)·눈금(R4/R6)·
  135.2→35.2와 172.5→72.5(R9/R11)·제지방량/권장섭취열량 혼입(R7b)·기울어진
  장(R3)·모호 빈칸(R6/R10)·교차/항등 보류(R11) 전부 일치.
- **뮤테이션 검증**: 규칙 17개를 하나씩 무력화 → 17/17 테스트 실패 확인 후 복구
  (R4 뮤테이션은 1차에서 생존 — _int가 3~4자리라 눈금 '55'를 못 무는 너무 좁은
  뮤테이션이었음. 임의 폭 정수 채택으로 고쳐 재검증 → 검출).
- `flutter analyze` 0 이슈 · `flutter test` 787/787 (기존 751 + 신규 36) ·
  `flutter build apk --debug` 성공.
- 이식 차이 3건(전부 주석으로 코드에 명기): ① 날짜는 실존 달력 검증(참조는 문자열이라
  "2026-13-45"도 출력 — Dart는 DateTime 롤오버 금지) ② R11 항등 허용오차를 참조의
  BFM 기준 max(0.8kg,8%) 대신 **폼과 같은** PBF 5.0%p로(파서가 폼보다 엄격하면 폼이
  받아줄 값을 파서만 버리고, 반대면 프리필 직후 경고가 떠 어리둥절 — 방향은 동일)
  ③ 항등 복원값(w−100)에 체중 하한 요구(통과시키면 프리필 직후 폼이 붉게 판정).
- **실기기 재실측(단계 3, 2026-08-23)**:
  - **크래시 1건 발견·수리** — 사진 선택 즉시 `NoClassDefFoundError(KoreanTextRecognizerOptions)`.
    플러그인이 한국어 아티팩트를 `compileOnly`로만 참조해(플러그인 build.gradle:53) **앱 gradle에
    `implementation("com.google.mlkit:text-recognition-korean:16.0.1")`이 별도로 필요**했다.
    빌드·analyze·테스트 787건이 전부 통과한 상태에서 실기기에서만 터지는 종류 — 단계 3이
    존재하는 이유 그 자체. `android/app/build.gradle.kts`에 근거 주석과 함께 추가.
  - 1번 장(InBody270): 측정일 2026-05-26 포함 **6칸 정답 + VFL 안전 빈칸** → VFL 수기 보완 후
    저장 → 운영 서버에 `source='member_self'`로 착지 확인(값 전부 정답).
  - 5번 장(비스듬히 촬영, 최난도): **5칸 전부 정답**(73.3/32.7/15.7/21.5/6) + BMR 안전 빈칸.
    장에 없는 날짜는 지어내지 않고 오늘 유지.
  - 두 장 모두 **오답 0** — 엔진이 달라도(Vision→ML Kit) 설계 속성이 유지됐다.

## 후속 작업

- 정련 에이전트가 세션 한도(새벽 2시 리셋)로 중단됐으나 **중단 전에 목표를 달성**한 상태였다.
  마지막 남긴 트윅 제안("ownership을 A 후보에도, A 임계 0.45")은 sheet3 PBF 빈칸 1개를 노리는
  것이었는데 **적용하지 않았다** — 미검증 트윅으로 오답 0 속성을 걸 이유가 없다.
- **iOS 이월**: google_mlkit_text_recognition podspec이 iOS 15.5 요구, 프로젝트는
  15.0 + Podfile 부재. iOS를 켤 때 Podfile 생성 + platform 15.5 상향 + Info.plist
  카메라/포토 사용 문구 추가가 한 세트다. 그때까지 버튼은 Android 전용
  (`_photoFillAvailable`) — iOS 안내문 "아직 없어요"는 계속 사실.
- 실기기 재실측(단계 3): `/sdcard/Pictures/inbody_sample_*.jpg` 5장으로 프리필 = 정답
  대조. EXIF 세로 사진의 크기 축 스왑 가드(`inbodyTokensFromOcr` 주석)가 실물에서
  맞는지 이때 함께 본다.

## 참조

- work_log/P18-inbody-upload-{backend,app,admin}.md · docs/API계약_v1.md v2.9 ·
  design/inbody-ocr/README.md
