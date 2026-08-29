import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/features/records/domain/inbody_sheet_parser.dart';

part 'inbody_sheet_reader.g.dart';

/// 결과지 사진 → 온디바이스 OCR → 파서. **이미지는 저장·전송하지 않는다** —
/// 결과지엔 이름·나이·성별이 함께 인쇄된다(P20 제품 결정). image_picker가 앱
/// 캐시에 만든 사본은 읽기가 끝나면 지운다.
///
/// 인식 실패는 예외가 아니라 [InbodySheetReadFailed]다 — 수기 입력이 곧 실패
/// 경로라(제품 결정) 호출부(시트)는 어떤 결과든 같은 폼으로 떨어뜨린다.

enum InbodyPhotoSource { gallery, camera }

sealed class InbodySheetReadOutcome {
  const InbodySheetReadOutcome();
}

/// 회원이 사진 선택을 스스로 물렸다 — 아무 말도 하지 않는다.
class InbodySheetReadCancelled extends InbodySheetReadOutcome {
  const InbodySheetReadCancelled();
}

/// 사진은 골랐지만 인식이 실패했다(엔진 오류·미지원 환경 포함).
class InbodySheetReadFailed extends InbodySheetReadOutcome {
  const InbodySheetReadFailed();
}

/// 인식 완료 — [result]가 빈 값일 수도 있다(0건 인식도 실패 화면이 아니라 폼이다).
class InbodySheetRead extends InbodySheetReadOutcome {
  const InbodySheetRead(this.result);
  final InbodySheetParseResult result;
}

abstract interface class InbodySheetReader {
  Future<InbodySheetReadOutcome> read(InbodyPhotoSource source);
}

/// ML Kit(한국어 스크립트) 구현.
class MlKitInbodySheetReader implements InbodySheetReader {
  MlKitInbodySheetReader();

  final ImagePicker _picker = ImagePicker();

  @override
  Future<InbodySheetReadOutcome> read(InbodyPhotoSource source) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source == InbodyPhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
    } catch (_) {
      // 픽커 자체가 못 뜨는 환경(플러그인 없음 등) — 수기 입력으로 폴백.
      return const InbodySheetReadFailed();
    }
    if (picked == null) return const InbodySheetReadCancelled();
    try {
      final (width, height) = await _imageSize(picked);
      // 인식기는 호출마다 만들고 닫는다 — 한국어 모델을 상주시켜 두기엔 이 기능이
      // 드물게 쓰이고(측정은 월 단위), 시트가 닫힌 뒤에도 네이티브 메모리를 잡는
      // 쪽이 손해다.
      final recognizer =
          TextRecognizer(script: TextRecognitionScript.korean);
      try {
        final recognized =
            await recognizer.processImage(InputImage.fromFilePath(picked.path));
        final tokens = inbodyTokensFromOcr(
          lines: [
            for (final block in recognized.blocks)
              for (final line in block.lines)
                (
                  line: _box(line.text, line.boundingBox),
                  elements: [
                    for (final e in line.elements) _box(e.text, e.boundingBox),
                  ],
                ),
          ],
          imageWidth: width,
          imageHeight: height,
        );
        return InbodySheetRead(InbodySheetParser.parse(tokens));
      } finally {
        await recognizer.close();
      }
    } catch (_) {
      return const InbodySheetReadFailed();
    } finally {
      // 이미지 폐기: image_picker가 앱 캐시에 만든 사본을 지운다. 갤러리에서 고른
      // 원본은 회원의 것 — 건드리지 않는다(카메라 촬영분도 캐시에만 생긴다).
      try {
        await File(picked.path).delete();
      } catch (_) {
        // 이미 없거나 파일시스템이 없는 환경 — 폐기 실패로 흐름을 막지 않는다.
      }
    }
  }

  /// 인코딩 헤더만 읽어 원본 픽셀 크기를 얻는다(전체 디코딩 없음).
  Future<(int, int)> _imageSize(XFile file) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await file.readAsBytes(),
    );
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (descriptor.width, descriptor.height);
      descriptor.dispose();
      return size;
    } finally {
      buffer.dispose();
    }
  }
}

OcrBox _box(String text, ui.Rect rect) => (
      text: text,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
    );

/// ML Kit 픽셀 박스(왼쪽-위 원점, y 아래로 증가).
typedef OcrBox = ({
  String text,
  double left,
  double top,
  double width,
  double height,
});

/// ML Kit 인식 결과 → 파서 토큰. 순수 함수 — 좌표 변환과 토큰 구성 규칙을
/// ML Kit 없이 검증하기 위해 분리했다.
///
/// **좌표 변환**: 파서(참조 구현 = macOS Vision)는 0~1 정규화 + y 위로 증가를
/// 전제한다(design/inbody-ocr/README.md "ML Kit 이식 주의"). 픽셀 박스를 이미지
/// 크기로 나누고 y축을 뒤집는다 — 파서의 부등호를 참조 구현과 문자 그대로 같게
/// 유지하기 위해서다.
///
/// **토큰 구성(라인/엘리먼트 양쪽 사용)**: Vision과 ML Kit은 토큰 분할 습성이
/// 다르다. 엘리먼트(공백 분리 단어)는 전부 넣고, **라인은 한글이 없을 때만**
/// 추가한다:
/// - 숫자 라인("72.5 (55.8~75.4)")은 값+범위가 한 토큰에 있어야 잡히는 R6/R9
///   조합을 재현한다. 같은 값의 엘리먼트가 중복돼도 모호성 판정(R6·R10)은
///   "다른 값"만 세므로 무해하다.
/// - 한글 라인("골격근량 35.6 …")을 넣으면 행 전체를 덮는 박스가 앵커와 별개의
///   한글 라벨이 되어, 행 소유권(R7b)이 자기 행의 값을 "남의 행"으로 오판한다
///   — 라벨·앵커 역할은 엘리먼트에만 맡긴다.
List<InbodyOcrToken> inbodyTokensFromOcr({
  required List<({OcrBox line, List<OcrBox> elements})> lines,
  required int imageWidth,
  required int imageHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return const [];

  // EXIF 방어: ML Kit은 EXIF 회전을 적용한 "세워진 이미지" 좌표를 주는데,
  // 인코딩 헤더의 크기는 회전 전 값일 수 있다(회전 90/270이면 가로세로가 바뀜).
  // 박스가 이미지 크기를 벗어나면 축이 뒤집힌 것 — 크기를 맞바꾼다.
  var w = imageWidth.toDouble();
  var h = imageHeight.toDouble();
  var maxRight = 0.0, maxBottom = 0.0;
  for (final entry in lines) {
    for (final b in [entry.line, ...entry.elements]) {
      maxRight = maxRight < b.left + b.width ? b.left + b.width : maxRight;
      maxBottom = maxBottom < b.top + b.height ? b.top + b.height : maxBottom;
    }
  }
  if ((maxRight > w || maxBottom > h) &&
      maxRight <= h &&
      maxBottom <= w) {
    final tmp = w;
    w = h;
    h = tmp;
  }

  InbodyOcrToken toToken(OcrBox b) => InbodyOcrToken(
        text: b.text,
        x: b.left / w,
        // y 반전: 픽셀 상단 원점 → 정규화 하단 원점. 박스의 y는 왼쪽-아래 모서리.
        y: 1 - (b.top + b.height) / h,
        w: b.width / w,
        h: b.height / h,
      );

  final hangul = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]');
  return [
    for (final entry in lines) ...[
      for (final e in entry.elements) toToken(e),
      if (!hangul.hasMatch(entry.line.text)) toToken(entry.line),
    ],
  ];
}

@riverpod
InbodySheetReader inbodySheetReader(Ref ref) => MlKitInbodySheetReader();
