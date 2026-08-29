/// 순수 도메인 — 수평계. Flutter/센서 의존 0(테스트 대상).
/// 목업 규칙: 수평이면 초록, 기울면 주황 + 각도 표시.
sealed class LevelState {
  const LevelState(this.angleDeg);
  final double angleDeg;
}

final class LevelOk extends LevelState {
  const LevelOk(super.angleDeg);
}

final class LevelTilted extends LevelState {
  const LevelTilted(super.angleDeg);
}

/// |각도| < 1°면 정렬(OK), 아니면 기울어짐(Tilted).
abstract final class LevelEvaluator {
  static const thresholdDeg = 1.0;

  static LevelState evaluate(double angleDeg) {
    return angleDeg.abs() < thresholdDeg ? LevelOk(angleDeg) : LevelTilted(angleDeg);
  }
}
