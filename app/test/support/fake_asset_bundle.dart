import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 계약서 시트 테스트용 가짜 자산 번들(P39) — DefaultAssetBundle로 감싸 시트에
/// 짧은/깨진 템플릿을 주입한다. 진짜 pt-v1 자산 렌더는 렌더러 골든과 실자산 통합
/// 테스트가 덮으므로, 게이트 분기(끝-스크롤·짧은 문서·값 누락)는 몇 줄짜리 템플릿으로
/// 빠르고 결정적으로 검증한다.
class FakeAssetBundle extends CachingAssetBundle {
  FakeAssetBundle(this.strings);

  /// 자산 경로 → 내용. 없는 키는 실제 번들처럼 예외를 던진다(자산 결손 경로 검증용).
  final Map<String, String> strings;

  @override
  Future<ByteData> load(String key) async {
    final s = strings[key];
    if (s == null) {
      throw FlutterError('FakeAssetBundle에 없는 자산: $key');
    }
    return ByteData.sublistView(utf8.encode(s));
  }
}
