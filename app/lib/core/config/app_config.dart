/// 앱 레벨 정적 설정.
///
/// ⚠️ 갭: API계약_v1.md의 Member 엔티티에는 센터명 필드가 없다(트레이너는
/// trainer_id만 보유). 이 앱은 "라이즈 컨디셔닝" 단일 센터 전제로 빌드되어
/// 센터명을 로컬 상수로 표시한다. 멀티 센터 전환 시 서버가 GET /v1/me
/// 응답 또는 v1.1의 `GET /v1/center`로 센터명을 내려줘야 한다.
abstract final class AppConfig {
  static const centerName = '라이즈 컨디셔닝';
  static const centerBranch = '강남';
  static const centerFullName = '$centerName 센터 ($centerBranch)';
}
