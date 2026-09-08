# R8/ProGuard 규칙 — **릴리스 빌드 전용 경로**라 디버그·테스트에서는 드러나지 않는다.
# (실제로 `flutter build apk --release`에서 처음 터졌다, P46.)

# ── ML Kit 텍스트 인식: 쓰지 않는 언어 모델 참조 무시 ─────────────────────
#
# `google_mlkit_text_recognition` 플러그인의 TextRecognizer.initialize()는 스크립트별
# 옵션(라틴/중국어/일본어/한국어/데바나가리)을 **한 메서드 안에서 전부 참조**한다.
# 우리는 인바디 결과지(한국어)만 읽으므로 `text-recognition-korean`만 의존에 넣었고
# (app/build.gradle.kts 주석 참조), 나머지 세 언어 클래스는 APK에 없다.
#
# R8은 그 참조를 "빠진 클래스"로 보고 컴파일을 중단한다. 세 모델을 다 넣으면 빌드는
# 통과하지만 **쓰지도 않는 모델이 APK를 수 MB 불린다** — 참조는 우리가 절대 타지 않는
# 분기(한국어 옵션을 넘긴다)에만 있으므로 경고를 끄는 쪽이 맞다.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder

# 한국어 인식기는 **반드시 남긴다.** 플러그인이 리플렉션 계열 경로로 옵션을 만들고
# (compileOnly로만 참조 — build.gradle.kts 주석의 NoClassDefFoundError 사고와 같은 자리),
# R8이 "아무도 안 부른다"고 판단해 지우면 실기기에서 사진을 고르는 순간 죽는다.
-keep class com.google.mlkit.vision.text.korean.** { *; }
