---
id: P22
title: 스토어 심사용 법률 문서 3종 작성 + 호스팅 준비
status: 진행 중
domain: cross
created: 2026-08-25
completed:
---

# P22 — 이용약관 · 개인정보처리방침 · 민감정보 동의

## 목표

P21 홀로우 감사가 최상위 P0로 올린 "스토어 심사 3종(약관·처리방침·계정삭제)" 중 문서 3종을 작성하고,
재빌드에도 살아남는 공개 URL로 서비스할 수 있게 준비한다. 배포는 하지 않는다(람이 직접).

- 이용약관
- 개인정보처리방침
- 민감정보(건강정보) 수집·이용 동의
- (추가) 계정·데이터 삭제 요청 안내 — Play가 **웹 URL을 강제**해서 함께 만듦

## 결정 사항

### 위치는 `admin/public/legal/` — `dist/`가 아니다
`firebase.json`의 hosting public이 `admin/dist`인데 `dist/`는 gitignore + 빌드마다 갈아엎힌다.
Vite는 `publicDir`(=`admin/public`)를 빌드 때 `outDir`로 **그대로 복사**하므로, 소스는 git에 남고
산출물은 매 빌드마다 자동으로 다시 깔린다. 별도 호스팅 타깃(`hosting:sites:create`)은 배포 권한이
필요해 이번 범위 밖. `npm run build` → `dist/legal/*.html` 5개 생성 확인함.

Hosting 우선순위상 정적 파일 정확 일치가 `**` → `/index.html` 리라이트보다 먼저라 SPA 폴백에
먹히지 않는다. 확장자 있는 URL(`/legal/privacy.html`)이 정식 주소다.

### 문서는 코드에서 역산한 사실만 쓴다
"있어 보이는데 없는 것"을 방침에 쓰면 그 자체가 허위 고지다. 실제로 걷어낸 것:

- **배경인물 자동 블러 — 없다.** `blurred: false` 하드코딩, 감지·블러 코드 0건
  (`background_person_banner.dart` 주석이 과거 거짓 문구 이력까지 남겨 뒀다).
  → 방침에 "안내만 하고 자동으로 가리지 않는다"고 사실대로 씀.
- **EXIF 제거 — 안 한다.** 다만 위치 권한을 선언하지 않아 GPS 태그는 물리적으로 안 생긴다.
- **분석·크래시·광고 SDK — 0개. 푸시 — 없다.** `GoogleService-Info.plist`에 `IS_GCM_ENABLED: true`가
  있지만 `firebase_messaging` 패키지가 없어 코드 경로 자체가 없다. 과다 고지 금지.
- **트레이너 프로필 사진 — 버킷에 없다.** `photo_url`은 센터가 입력하는 외부 http(s) 주소고,
  `storage.rules`의 `/staff/photos/`는 `read, write: if false`로 막혀 있다.
- **결제 — 앱에서 안 받는다.** PG 연동 0건. 카드번호를 수집 항목에 넣으면 거짓.

### 국외이전은 Firebase Auth 하나뿐
`gcloud`로 실측: Firestore·Storage 버킷·Cloud Run 전부 `asia-northeast3`(서울).
반면 **Firebase Authentication은 미국 데이터센터 전용**(Google 공식 문서 명시)이라 휴대폰번호·인증
메타데이터·로그인 IP만 국외로 나간다. 법 제28조의8 제1항 제3호 가목(계약 이행 처리위탁 + 처리방침
공개)으로 처리하고, 제2항 5개 고지사항을 표로 실었다 — **거부의 효과**까지 사실대로
("거부하면 로그인 불가, 단 센터 이용은 그대로").

### 민감정보 범위를 3종으로 확장
앱 동의 토글 문구는 "인바디·체형사진"만 말하는데, 실제로는 **부상·통증 메모**(`flags[injury].note`)도
건강정보다 — 어드민이 입력하고 회원 앱이 받아 본다. 문서는 3종 전부를 동의 범위로 적었다.
→ 앱 문구와 서버 가드를 문서에 맞추는 것이 후속 작업.

## 진행 단계

- [x] 0. 병렬 리서치 3갈래(국내법 / 스토어 정책 / 코드 실사) 투입
- [x] 1. 코드 실사 — 수집 항목·권한·SDK·저장 경로·접근 통제 전수 확인
- [x] 2. 1차 출처 검증 — 법 제15·23·28의8·30조, 전자상거래법 보존기간, 안전성 확보조치 기준 제8조
- [x] 3. 인프라 실측 — `gcloud`로 Firestore/Storage/Run 리전, PITR·백업 보존, 로그 보존 확인
- [x] 4. 문서 4종 작성 (`admin/public/legal/`)
- [x] 5. `npm run build`로 `dist/legal/` 복사 검증 + 자립성(외부 리소스 0) 검사
- [ ] 6. 람이 플레이스홀더 채우기 → 배포 → 스토어 등록

## 변경 파일

- `admin/public/legal/index.html` — 허브(4종 카드)
- `admin/public/legal/terms.html` — 이용약관 22조 + 부칙
- `admin/public/legal/privacy.html` — 개인정보처리방침 17조
- `admin/public/legal/sensitive-consent.html` — 민감정보 동의 12항 + 서면 동의 확인란(인쇄용)
- `admin/public/legal/account-deletion.html` — 계정·데이터 삭제 요청(한국어 + 영문 병기)

스타일: 다크(#14181f) · 저채도 액센트 · Pretendard 폴백 · `keep-all` · 76ch · 인라인 CSS ·
JS는 "맨 위로" 버튼 하나 · 외부 리소스 0(오프라인 `file://` 동작) · 인쇄 시 라이트 톤 전환.

## 검증

- `npm run build` 그린 → `dist/legal/*.html` 5개 확인
- 외부 리소스 로드(`<link>`/`<script src>`/`@import`/`url()`/`<img>`) **0건**
- div/table/details 태그 균형 5개 파일 전부 일치
- 인프라 실측값: Firestore `asia-northeast3` · PITR 활성 · `versionRetentionPeriod=604800s`,
  Storage 버킷 `ASIA-NORTHEAST3` region, Cloud Run `asia-northeast3`, 로그 버킷 30일/400일

## 후속 작업

문서가 약속한 것 중 **아직 코드·설정이 못 따라오는 것**(배포 전 처리):

1. **계정 삭제 — 앱 내 경로 부재.** Apple 5.1.1(v)·Play 모두 **앱 안에서** 시작할 수 있어야 한다.
   지금은 웹 요청 페이지뿐이라 심사에서 걸린다. `DELETE /v1/me` 신설 + 마이 탭 진입점 필요.
2. **체형사진 파기 수단 0.** `storage.rules`가 `allow delete: if false`, 서버에도 삭제 API 없음.
   방침이 "요청하면 파기"라고 약속했으므로 운영자 수동 삭제 절차라도 문서화하거나 API를 만들어야 한다.
3. **접속기록 보존 2년.** 민감정보 처리 시스템이라 「안전성 확보조치 기준」 제8조상 2년인데
   현재 Cloud Logging `_Default`는 **30일**. 방침 표에 2년이라 적었으므로 설정을 올려야 참이 된다.
4. **부상 메모 동의 게이트.** 서버가 `flags[injury]` 쓰기를 sensitive consent로 막지 않는다.
   앱 동의 토글 문구도 "인바디·체형사진"만 말한다 — 문서 범위(3종)에 맞춰 둘 다 수정.
5. **앱 내 약관·방침 링크.** 양대 스토어가 **앱 안에서도** 접근 가능할 것을 요구한다(메타데이터 필드만으론 부족).
6. **법인 명의 개발자 계정.** Apple 5.1.1(ix) — healthcare는 개인 개발자 계정 제출 시 리젝 리스크.

## 참조

- 선행: [P21-hollow-feature-audit.md](P21-hollow-feature-audit.md) (스토어 심사 3종 부재를 P0로 지목)
- 접근 통제 근거: `backend/internal/api/service.go` `checkBodyPhotoAccess`·`checkMemberScope`,
  `storage.rules`, `firestore.rules`
- 동의 모델: `backend/internal/domain/member.go` `Consent`·`SensitiveConsentValid`
