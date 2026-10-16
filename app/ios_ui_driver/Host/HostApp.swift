import SwiftUI

// XCUITest 러너용 빈 호스트 — 실제 조작 대상은 설치된 com.han.rise(번들 ID로 구동).
@main
struct HostApp: App {
  var body: some Scene { WindowGroup { Text("P75 driver host") } }
}
