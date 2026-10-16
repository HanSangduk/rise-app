import XCTest

/// iOS 실기기 UI 드라이버(P77) — 설치된 라이즈 앱(com.han.rise, lib/main.dart 릴리스 빌드)을 사람처럼 조작한다.
///
/// 질문: reCAPTCHA 사파리 시트를 (a) 완료 버튼 (b) 왼쪽 가장자리 스와이프 (c) 아래로 스와이프로 닫은 뒤
/// "인증번호 받기"를 다시 누르면 시트가 다시 뜨는가(정상), 아니면 즉시 "창이 닫혔어요"만 반복되는가(갇힘 —
/// AuthURLPresenter.isPresenting이 풀리지 않는 경우)?
/// 번호는 Firebase 콘솔 등록 테스트 번호(실 SMS 없음). 인증번호 화면까지만 가고 코드는 넣지 않는다.
final class DriverUITests: XCTestCase {
  private let phone = "01055556666"
  private let start = Date()

  override func setUp() {
    continueAfterFailure = true
  }

  private func log(_ s: String) {
    print(String(format: "[P75D] t=%6.1fs %@", Date().timeIntervalSince(start), s))
  }

  private func element(_ app: XCUIApplication, containing s: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
  }

  private func safariDone(_ app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label IN %@", ["완료", "Done", "닫기", "Close"])).firstMatch
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }

  private func launchFresh() -> XCUIApplication {
    let app = XCUIApplication(bundleIdentifier: "com.han.rise")
    app.terminate()
    app.launch()
    let send = element(app, containing: "인증번호 받기")
    XCTAssertTrue(send.waitForExistence(timeout: 40), "로그인 화면이 안 떴다")
    log("로그인 화면")
    return app
  }

  /// 번호를 넣고 "인증번호 받기" — 키보드가 버튼을 가리면 로고를 눌러 내린다.
  private func requestCode(_ app: XCUIApplication, typeNumber: Bool = true) {
    if typeNumber {
      let field = app.textFields.firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 10), "번호 입력란 없음")
      field.tap()
      field.typeText(phone)
      log("번호 입력: \(field.value as? String ?? "?")")
    }
    let send = element(app, containing: "인증번호 받기")
    if !send.isHittable { element(app, containing: "CONDITIONING").tap() }
    send.tap()
    log("인증번호 받기 탭")
  }

  enum Outcome: String { case sheet, codeScreen, closedError, pageNotFound, timeout }

  /// 다음 상태가 나올 때까지 0.25초 간격으로 본다.
  private func waitOutcome(_ app: XCUIApplication, timeout: TimeInterval, sheetCounts: Bool) -> Outcome {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
      if element(app, containing: "Page Not Found").exists || element(app, containing: "no routes for location").exists { return .pageNotFound }
      if element(app, containing: "인증번호 입력").exists { return .codeScreen }
      if sheetCounts && safariDone(app).exists { return .sheet }
      if element(app, containing: "창이 닫혔").exists { return .closedError }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return .timeout
  }

  private func dismissSheet(_ app: XCUIApplication, how: String) {
    switch how {
    case "done":
      safariDone(app).tap()
    case "edge":
      let s = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
      let e = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
      s.press(forDuration: 0.05, thenDragTo: e, withVelocity: .fast, thenHoldForDuration: 0.05)
    default: // "down"
      let s = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
      let e = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
      s.press(forDuration: 0.05, thenDragTo: e, withVelocity: .fast, thenHoldForDuration: 0.05)
    }
    log("시트 닫기 시도: \(how)")
  }

  /// 시트를 [how]로 닫고 다시 요청 — 다시 요청이 시트를 띄우거나 인증번호 화면에 도착하면 통과(= 갇히지 않음).
  /// 판정할 수 없는 경우(시트를 못 잡음·닫기 전에 끝남·제스처 미지원)는 통과가 아니라 **건너뜀**으로 남긴다.
  private func runDismissScenario(_ how: String) throws {
    let app = launchFresh()
    requestCode(app)
    let first = waitOutcome(app, timeout: 45, sheetCounts: true)
    log("첫 요청 결과: \(first.rawValue)")
    shot("\(how)-1-first-\(first.rawValue)")
    guard first == .sheet else {
      XCTAssertNotEqual(first, .pageNotFound, "라우터 누수 재발")
      throw XCTSkip("판정 불가: 시트를 못 잡았다(\(first.rawValue)) — reCAPTCHA가 먼저 끝났거나 안 떴다")
    }
    dismissSheet(app, how: how)
    let afterDismiss = waitOutcome(app, timeout: 8, sheetCounts: false)
    log("닫은 뒤: \(afterDismiss.rawValue) · 시트 아직 있음=\(safariDone(app).exists)")
    shot("\(how)-2-after-dismiss-\(afterDismiss.rawValue)")
    if afterDismiss == .codeScreen {
      throw XCTSkip("판정 불가: 닫기 전에 reCAPTCHA가 끝나 인증번호 화면으로 갔다")
    }
    if safariDone(app).exists {
      throw XCTSkip("\(how) 제스처로는 시트가 닫히지 않는다(제스처 미지원 — 갇힘 판정 대상 아님)")
    }
    // 다시 요청
    let retryAt = Date()
    requestCode(app, typeNumber: false)
    let retry = waitOutcome(app, timeout: 45, sheetCounts: true)
    let dt = Date().timeIntervalSince(retryAt)
    log(String(format: "다시 요청 결과: %@ (%.1fs)", retry.rawValue, dt))
    shot("\(how)-3-retry-\(retry.rawValue)")
    XCTAssertNotEqual(retry, .pageNotFound, "라우터 누수 재발")
    XCTAssertTrue(retry == .sheet || retry == .codeScreen,
                  "\(how)로 닫은 뒤 다시 요청이 막혔다(\(retry.rawValue)) — Firebase 시트 상태가 갇혔을 수 있다")
    if retry == .sheet {
      // 최종 도착은 **기록만** 한다 — 같은 기기에서 연달아 reCAPTCHA를 요청하면 시트가 자동 통과하지 않고 머문다
      // (P77 실측). 갇힘 판정(시트가 다시 떴나)은 위 단언이 끝냈다.
      let fin = waitOutcome(app, timeout: 45, sheetCounts: false)
      log("시트 다시 뜬 뒤 최종(기록만): \(fin.rawValue)")
      shot("\(how)-4-final-\(fin.rawValue)")
    }
  }

  func test00_happyPath_realApp() {
    let app = launchFresh()
    requestCode(app)
    var o = waitOutcome(app, timeout: 45, sheetCounts: true)
    log("결과1: \(o.rawValue)")
    if o == .sheet {
      shot("happy-1-sheet")
      o = waitOutcome(app, timeout: 45, sheetCounts: false)
      log("결과2: \(o.rawValue)")
    }
    shot("happy-2-final-\(o.rawValue)")
    XCTAssertEqual(o, .codeScreen, "실제 앱이 인증번호 화면에 도착하지 못함")
  }

  func test01_dismissByDoneButton() throws { try runDismissScenario("done") }
  func test02_dismissByEdgeSwipe() throws { try runDismissScenario("edge") }
  func test03_dismissBySwipeDown() throws { try runDismissScenario("down") }
}
