// 체형사진 목록의 불량 날짜 1건이 타임라인 전체를 숨기지 않는다(P73).
//
// 인바디·수업 기록·hw-check는 `DateTime.tryParse` + 그 건만 스킵인데, 체형사진만
// `DateTime.parse`(throw)였다. 예외는 guardApi에서 Err로 접히고, 기록 탭은 그것을
// "사진 없음"으로 위장하지 않고 `bodyPhotosFailed`로 정직하게 알린다 — 그래서 결과는
// "레코드 하나가 깨지면 수개월 치 타임라인이 통째로 '불러오지 못했어요'"였다.
// 여기서는 **실제 `BodyCheckRepositoryImpl`**을 돌린다(함수가 아니라 배선).

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/data/body_check_remote_data_source.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_impl.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';

void main() {
  BodyCheckRepositoryImpl repo(String listBody) =>
      BodyCheckRepositoryImpl(BodyCheckRemoteDataSource(_StubDio(listBody)), _NoLoader());

  test('날짜가 깨진 레코드는 그 건만 빠지고 나머지는 보인다', () async {
    // "깨진" 값은 **파서가 정말 null을 돌려주는 모양**으로 고른다(records_repository_failure_test와
    // 같은 관례): 자릿수가 안 맞는 '2026-8-2', 빈 문자열, 'not-a-date'. '2026-13-99'처럼 형식은
    // 맞고 범위만 벗어난 값은 Dart DateTime이 예외 없이 이월 정규화하므로 걸러지지 않는다 —
    // 그런 값은 서버(CreateBodyPhoto v2.37, Go time.Parse는 범위까지 본다)가 저장 단계에서 막는다.
    final result = await repo('''
[{"id":"a","member_id":"m1","pose":"stand","direction":"front","date":"2026-08-01","storage_path":"p/a.jpg"},
 {"id":"b","member_id":"m1","pose":"stand","direction":"front","date":"2026-8-2","storage_path":"p/b.jpg"},
 {"id":"c","member_id":"m1","pose":"tpose","direction":"side","date":"","storage_path":"p/c.jpg"},
 {"id":"e","member_id":"m1","pose":"tpose","direction":"side","date":"not-a-date","storage_path":"p/e.jpg"},
 {"id":"d","member_id":"m1","pose":"fold","direction":"back","date":"2026-08-03","storage_path":"p/d.jpg"}]
''').fetchPhotos('m1');

    expect(result, isA<Ok<List<BodyPhotoEntry>>>(), reason: '불량 1건이 목록 전체를 Err로 접었다');
    final entries = (result as Ok<List<BodyPhotoEntry>>).value;
    expect(entries.map((e) => e.id).toList(), ['a', 'd']);
    expect(entries.last.direction, BodyDirection.back);
  });

  test('정상 목록은 그대로 전부 온다', () async {
    final result = await repo('''
[{"id":"a","member_id":"m1","pose":"stand","direction":"front","date":"2026-08-01","storage_path":"p/a.jpg"}]
''').fetchPhotos('m1');
    expect((result as Ok<List<BodyPhotoEntry>>).value, hasLength(1));
  });
}

class _NoLoader implements BodyPhotoLoader {
  @override
  void clear() {}

  @override
  void evict(String storagePath) {}

  @override
  Uint8List? peek(String storagePath) => null;

  @override
  Future<Result<Uint8List>> load(String storagePath) => throw UnimplementedError();
}

/// `GET /v1/body-photos`에 고정 본문을 돌려주는 최소 Dio.
class _StubDio with DioMixin implements Dio {
  _StubDio(String body) {
    options = BaseOptions();
    httpClientAdapter = _Adapter(body);
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
