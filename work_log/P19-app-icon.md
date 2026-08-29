---
id: P19
title: 회원 앱 런처 아이콘 + 표시 이름(라이즈)
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P19 — 회원 앱 런처 아이콘 + 표시 이름

## 목표

런처에 기본 Flutter 아이콘과 패키지명 `rise_member`가 그대로 노출되던 상태를 브랜드 실물로
교체한다. 자산은 `design/brand/`에 준비돼 있었다(마스터·적응형 전경·모노 — 벡터 재현,
`design/brand/README.md` 참조). 이 P는 **적용**만 담당한다.

- Android: 적응형 아이콘(전경 PNG + 배경 단색 `#F6F4EF` + 안드로이드 13+ 모노) + 레거시 mipmap
- iOS: 1024 마스터(불투명 — App Store 알파 금지 요건)
- 표시 이름: 안드로이드 `android:label` · iOS `CFBundleDisplayName` → **라이즈**

## 결정 사항

### 1. flutter_launcher_icons `0.14.4` — 기억이 아니라 pub.dev API로 확인

`curl https://pub.dev/api/packages/flutter_launcher_icons` → latest `0.14.4`(2026-08-23 기준).
`adaptive_icon_monochrome` 키는 **0.14.0부터** 지원(CHANGELOG #497로 확인 — 추측 아님).
실행 커맨드는 `dart run flutter_launcher_icons`(`:generate`는 설정 템플릿 생성용이라 안 씀).

### 2. `adaptive_icon_foreground_inset: 0` — 기본값 16%면 마크가 이중 축소된다

도구 소스(`lib/config/config.dart`)에서 inset 기본값이 **16**임을 확인했다. 생성되는 적응형
XML은 전경·모노를 `<inset android:inset="N%">`로 감싸는데, 준비된 `appicon-fg.png`는 1024
캔버스가 적응형 레이어(108dp) **전체**에 대응하고 마크가 이미 세이프존(66/108) 안에 배치돼
있다. 기본값을 그대로 두면 세이프존 배치 위에 16%가 또 얹혀 마크가 과소해진다 → **0으로 고정**.
같은 inset이 모노 레이어에도 적용되므로(소스 확인) 모노도 함께 0.

### 3. 자산은 `app/assets/brand/`로 복사 — pubspec `assets:`에는 미등록

pubspec 기준 상대경로 `../design/brand/...`는 패키지 루트 밖이라 도구가 못 찾을 수 있어
복사본을 둔다. **소스 오브 트루스는 `design/brand/`**(pubspec 주석에 명시 — 마크 수정 시
재생성 파이프라인을 돌리고 다시 복사). 아이콘 생성 입력일 뿐 런타임에 안 쓰이므로
`flutter: assets:`에는 등록하지 않았다 — APK `flutter_assets/`에 안 실림(unzip으로 확인, 0건).

### 4. 표시 이름은 "라이즈 컨디셔닝"이 아니라 **라이즈**

런처 라벨은 길면 잘린다(안드로이드 홈 화면 ~10자 내외에서 말줄임). iOS `CFBundleName`은
시스템 내부 식별용이라 ASCII `rise_member` 유지, `CFBundleDisplayName`만 한글.

### 5. `min_sdk_android: 24` — 프로젝트 실제 minSdk와 일치

`build.gradle.kts`가 `flutter.minSdkVersion`(Flutter 3.44 기본 24)을 쓴다. 24 < 26이므로
레거시 mipmap도 함께 생성된다(API 26+는 anydpi-v26 XML이 우선).

### 6. `remove_alpha_ios`는 안 씀

마스터가 애초에 RGB 불투명(알파 채널 없음)이고, 생성된 1024 출력도 `sips -g hasAlpha` →
`no`로 확인했다. 불필요한 재합성 옵션을 얹지 않는다.

## 진행 단계

- [x] pub.dev API로 최신 stable(0.14.4) + 설정 키(README/CHANGELOG/소스) 확인
- [x] `design/brand/gen/` 3종 → `app/assets/brand/` 복사
- [x] pubspec에 dev_dependency + `flutter_launcher_icons:` 설정 추가
- [x] `dart run flutter_launcher_icons` 생성 실행
- [x] AndroidManifest `android:label` · Info.plist `CFBundleDisplayName` → 라이즈
- [x] 산출물·APK 검증 (아래 "검증")

## 변경 파일

- `app/pubspec.yaml` — dev_dependency `flutter_launcher_icons: ^0.14.4` + 설정 블록
- `app/assets/brand/appicon-{master,fg,mono}.png` — design/brand 복사본(신규)
- `app/android/app/src/main/AndroidManifest.xml` — `android:label` → 라이즈
- `app/ios/Runner/Info.plist` — `CFBundleDisplayName` → 라이즈
- 생성물(도구 산출):
  - `app/android/app/src/main/res/mipmap-{m,h,x,xx,xxx}dpi/ic_launcher.png` — 레거시 교체
  - `app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — 적응형(배경 색 + 전경/모노 inset 0%)
  - `app/android/app/src/main/res/drawable-*dpi/ic_launcher_{foreground,monochrome}.png`
  - `app/android/app/src/main/res/values/colors.xml` — `ic_launcher_background` `#F6F4EF`(신규)
  - `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/` — 25슬롯 전체 교체

## 검증

- 적응형 XML 실물 확인: `@color/ic_launcher_background` + 전경·**모노** 레이어 모두 참조, inset `0%`
- 전경/모노 drawable 크기 정합: xxxhdpi 432×432(=108dp×4) — 1024 캔버스→풀레이어 매핑 확인
- iOS `Contents.json` 25슬롯 ↔ PNG 파일 전수 대조(누락 0, 고아 0), 1024 출력 `hasAlpha: no`
- `flutter analyze` — 이슈 0
- `flutter test` — **738건 전체 통과**. 첫 실행에서 `records_inbody_write_test` 1건이 떨어졌으나
  단독 실행·전체 재실행 모두 그린(플레이크 — 이번 변경은 Dart 코드 무접촉이라 인과 없음)
- `flutter build apk --debug` — 성공. `aapt2 dump badging`으로 `application-label: '라이즈'`,
  unzip으로 적응형 XML·모노 drawable·레거시 mipmap이 APK에 실렸고 기본 Flutter 아이콘 잔재
  없음(ic_launcher 전 밀도 덮어씀), `flutter_assets/assets/brand` 0건 확인
- 실기기 설치는 안 함(람이 직접)

## 후속 작업

- 실기기에서 런처·설정 앱·테마 아이콘(안드로이드 13+ 머티리얼 유) 육안 확인 — 람
- iOS 18+ 다크/틴트 아이콘(`image_path_ios_dark_transparent` 등)은 v1 범위 밖 — 필요해지면
  design/brand 파이프라인에 다크 변형 추가 후 같은 설정으로 재생성
- `records_inbody_write_test` 플레이크 원인은 별도 P로(전체 실행 시 간헐 — 이번 범위 밖)

## 참조

- `design/brand/README.md` — 자산 유래·색·재생성 파이프라인(소스 오브 트루스)
- flutter_launcher_icons 0.14.4: pub.dev CHANGELOG(#497 monochrome), `lib/android.dart`
  (inset 래핑), `lib/config/config.dart`(inset 기본 16)
