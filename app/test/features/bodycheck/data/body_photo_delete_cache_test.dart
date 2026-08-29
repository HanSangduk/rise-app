// 삭제와 캐시 비우기가 짝이 되는가(P31).
//
// **이 파일은 살아남은 뮤테이션 때문에 생겼다.** 뷰어 쪽 테스트가 "캐시를 비운다"를
// 검사한다고 적어 놓고 실은 가짜 리포지토리가 받은 인자만 보고 있었다 — 진짜
// 리포지토리에서 `evict` 호출을 통째로 지워도 전부 통과했다. 여기서는 **실제
// `BodyCheckRepositoryImpl`**을 돌린다.
//
// 왜 중요한가: 캐시가 남으면 삭제가 거짓말이 된다. 서버는 지웠는데 목록 갱신이
// 실패하면(비행기 모드) 방금 "완전히 지워졌다"고 들은 사진이 캐시에서 그대로
// 다시 그려진다.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/data/body_check_remote_data_source.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_impl.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';

void main() {
  const path = 'members/m1/body/stand-1.jpg';

  ({BodyCheckRepositoryImpl repo, _SpyLoader loader, _StubDio dio}) build({
    int status = 204,
  }) {
    final dio = _StubDio(status);
    final loader = _SpyLoader();
    return (
      repo: BodyCheckRepositoryImpl(BodyCheckRemoteDataSource(dio), loader),
      loader: loader,
      dio: dio,
    );
  }

  test('삭제에 성공하면 그 사진의 캐시를 비운다', () async {
    final t = build();

    final result = await t.repo.deletePhoto(id: 'p1', storagePath: path);

    expect(result, isA<Ok<void>>());
    expect(t.dio.deleted, ['/v1/body-photos/p1']);
    expect(t.loader.evicted, [path], reason: '캐시가 남으면 지운 사진이 다시 그려진다');
  });

  test('삭제에 실패하면 캐시를 건드리지 않는다', () async {
    // 먼저 비우면 멀쩡한 사진의 캐시만 날아가고, 최악에는 파기되지 않은 사진을
    // "지워진 것처럼" 보이게 만든다.
    final t = build(status: 500);

    final result = await t.repo.deletePhoto(id: 'p1', storagePath: path);

    expect(result, isA<Err<void>>());
    expect(t.loader.evicted, isEmpty);
  });

  test('경로가 없는 옛 레코드는 서버만 지우고 조용히 넘어간다', () {
    // v2.10 이전에 저장된 레코드는 storage_path가 비어 있다. 빈 문자열로
    // evict를 부르면 아무것도 안 지우면서 의도만 흐려진다.
    for (final p in [null, '']) {
      final t = build();
      expect(() => t.repo.deletePhoto(id: 'p1', storagePath: p), returnsNormally);
      expect(t.loader.evicted, isEmpty);
    }
  });
}

class _SpyLoader implements BodyPhotoLoader {
  final evicted = <String>[];

  @override
  void clear() {}

  @override
  void evict(String storagePath) => evicted.add(storagePath);

  @override
  Uint8List? peek(String storagePath) => null;

  @override
  Future<Result<Uint8List>> load(String storagePath) => throw UnimplementedError();
}

/// `DELETE /v1/body-photos/{id}` 호출만 기록하는 최소 Dio.
class _StubDio with DioMixin implements Dio {
  _StubDio(this._status) {
    options = BaseOptions();
    httpClientAdapter = _Adapter(_status, deleted);
  }

  final int _status;
  final deleted = <String>[];
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.deleted);
  final int status;
  final List<String> deleted;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    if (options.method == 'DELETE') deleted.add(options.path);
    return ResponseBody.fromString('', status);
  }

  @override
  void close({bool force = false}) {}
}
