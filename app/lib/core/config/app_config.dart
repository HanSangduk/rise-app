/// 앱 레벨 정적 설정.
///
/// [centerFullName]은 **서버 값이 없을 때만 쓰는 임시 표시**다(P56 L10). 센터 상호의
/// 출처는 어드민 "센터 신원"이 저장하는 `GET /v1/public/center`(v2.29)이고, 화면은
/// `centerDisplayNameProvider`(features/auth/presentation/center_contact_provider.dart)를
/// 통해 읽는다 — 이 상수를 화면에 직접 찍지 말 것. 미등록·미로드 폴백에서만 나온다.
///
/// 종전엔 `'$centerName 센터 (강남)'`처럼 지점명까지 박혀 있었다 — P48 목업에서 온 값이고
/// 실제 지점을 확인한 근거가 없었다. 검증 못 한 사실을 회원에게 사실처럼 찍지 않기 위해
/// 지점명은 뺐고, 어드민 폴백(`CENTER_NAME_FALLBACK`)과 같은 문자열로 맞췄다 — 두 화면이
/// 등록 전 상태에서 서로 다른 이름을 말하지 않게.
abstract final class AppConfig {
  static const centerName = '라이즈 컨디셔닝';
  static const centerFullName = '$centerName 센터';
}
