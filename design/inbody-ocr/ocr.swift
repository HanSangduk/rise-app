// 인바디 결과지 OCR 실측 하네스(P18 v2 게이트 ③).
//
// 앱은 ML Kit을 쓰지만 여기선 macOS Vision으로 돌린다 — 목적은 엔진 벤치마크가 아니라
// "실물 결과지에서 앵커 라벨과 값을 짝지을 수 있는가"라는 파싱 규칙의 성립 여부다.
// 출력: 신뢰도 \t x \t y \t w \t h \t 텍스트 (좌표는 0~1 정규화, y는 아래가 0)
import Vision
import AppKit

guard CommandLine.arguments.count > 1,
      let img = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: ocr <image>\n".data(using: .utf8)!)
    exit(1)
}

let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.recognitionLanguages = ["ko-KR", "en-US"]
// 언어 교정은 끈다 — 라벨엔 도움이 되지만 숫자를 "그럴듯한 단어"로 바꿔버리는 쪽이 치명적이다.
req.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([req])
for obs in req.results ?? [] {
    guard let c = obs.topCandidates(1).first else { continue }
    let b = obs.boundingBox
    print("\(c.confidence)\t\(b.origin.x)\t\(b.origin.y)\t\(b.size.width)\t\(b.size.height)\t\(c.string)")
}
