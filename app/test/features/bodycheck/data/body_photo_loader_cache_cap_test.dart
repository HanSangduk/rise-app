import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';

/// Storage 가짜 — `getData`만 있다. 배선 시험(실제 [FirebaseBodyPhotoLoader.load]·[peek])이 시험 전용
/// static(`debugPut`)만 부르던 자리를 메운다: 그 static은 `_put`을 직접 부르므로 `load`가 캐시를
/// 우회해도(날 맵 쓰기·상한 없음) 초록이었다.
class _FakeStorage extends Fake implements FirebaseStorage {
  _FakeStorage(this.onGet);
  final Future<Uint8List?> Function(String path) onGet;
  int calls = 0;

  @override
  Reference ref([String? path]) => _FakeRef(this, path ?? '');
}

class _FakeRef extends Fake implements Reference {
  _FakeRef(this._storage, this._path);
  final _FakeStorage _storage;
  final String _path;

  @override
  Future<Uint8List?> getData([int maxSize = 10485760]) {
    _storage.calls++;
    return _storage.onGet(_path);
  }
}

// 체형사진 바이트 캐시는 **개수 상한**이 있고 가장 오래 안 쓴 것부터 빠진다(P74).
//
// 종전엔 로그아웃 전까지 본 사진 원본이 전부 남았다 — 타임라인을 오가며 수십 장을 보면 수십 MB가
// 세션 내내 메모리에 있었다. 상한은 "최근에 본 것은 다시 받지 않는다"는 캐시의 목적을 지키는
// 선(비교 화면 2장 + 스크러버 왕복)보다 넉넉하게 40으로 뒀다.
void main() {
  setUp(FirebaseBodyPhotoLoader.clearCache);
  tearDown(FirebaseBodyPhotoLoader.clearCache);

  Uint8List bytes(int i) => Uint8List.fromList([i]);

  test('상한을 넘으면 가장 오래 전에 넣은 것부터 빠진다', () {
    for (var i = 0; i < FirebaseBodyPhotoLoader.maxEntries + 5; i++) {
      FirebaseBodyPhotoLoader.debugPut('p/$i.jpg', bytes(i));
    }
    final keys = FirebaseBodyPhotoLoader.debugCachedPaths();
    expect(keys, hasLength(FirebaseBodyPhotoLoader.maxEntries));
    expect(keys.first, 'p/5.jpg', reason: '0~4가 순서대로 밀려났다');
    expect(keys.last, 'p/${FirebaseBodyPhotoLoader.maxEntries + 4}.jpg');
  });

  test('다시 넣은(최근 사용) 항목은 뒤로 옮겨져 살아남는다', () {
    for (var i = 0; i < FirebaseBodyPhotoLoader.maxEntries; i++) {
      FirebaseBodyPhotoLoader.debugPut('p/$i.jpg', bytes(i));
    }
    FirebaseBodyPhotoLoader.debugPut('p/0.jpg', bytes(0)); // 가장 오래된 것을 다시 사용
    FirebaseBodyPhotoLoader.debugPut('p/new.jpg', bytes(99)); // 하나 넘친다
    final keys = FirebaseBodyPhotoLoader.debugCachedPaths();
    expect(keys, contains('p/0.jpg'), reason: '최근에 다시 쓴 0번은 남아 있어야 한다');
    expect(keys, isNot(contains('p/1.jpg')), reason: '가장 오래 안 쓴 1번이 빠져야 한다');
    expect(keys.last, 'p/new.jpg');
  });

  test('읽기 히트(peek)도 최근 사용으로 갱신한다 — 비교 화면이 두 장을 번갈아 읽는다', () {
    for (var i = 0; i < FirebaseBodyPhotoLoader.maxEntries; i++) {
      FirebaseBodyPhotoLoader.debugPut('p/$i.jpg', bytes(i));
    }
    // 실제 인스턴스의 peek — 캐시 히트는 Storage를 건드리지 않으므로 가짜 없이도 돈다.
    final loader = FirebaseBodyPhotoLoader();
    expect(loader.peek('p/0.jpg'), bytes(0)); // 가장 오래된 것을 읽는다
    FirebaseBodyPhotoLoader.debugPut('p/new.jpg', bytes(99)); // 하나 넘친다
    final keys = FirebaseBodyPhotoLoader.debugCachedPaths();
    expect(keys, contains('p/0.jpg'), reason: '방금 읽은 0번은 남아 있어야 한다(읽기가 순서를 갱신하지 않으면 여기서 빠진다)');
    expect(keys, isNot(contains('p/1.jpg')), reason: '가장 오래 안 쓴 1번이 빠져야 한다');
    expect(loader.peek('p/missing.jpg'), isNull, reason: '없는 경로는 null — 캐시에 빈 항목을 만들지 않는다');
    expect(FirebaseBodyPhotoLoader.debugCachedPaths(), hasLength(FirebaseBodyPhotoLoader.maxEntries));
  });

  test('읽기 히트(load)는 다시 받지 않고 최근 사용으로 갱신한다', () async {
    for (var i = 0; i < FirebaseBodyPhotoLoader.maxEntries; i++) {
      FirebaseBodyPhotoLoader.debugPut('p/$i.jpg', bytes(i));
    }
    final storage = _FakeStorage((_) async => bytes(7));
    final loader = FirebaseBodyPhotoLoader(storage);
    final r = await loader.load('p/0.jpg');
    expect(r, isA<Ok<Uint8List>>());
    expect((r as Ok<Uint8List>).value, bytes(0), reason: '캐시의 바이트 그대로');
    expect(storage.calls, 0, reason: '히트인데 Storage를 다시 불렀다');
    FirebaseBodyPhotoLoader.debugPut('p/new.jpg', bytes(99)); // 하나 넘친다
    expect(FirebaseBodyPhotoLoader.debugCachedPaths(), contains('p/0.jpg'), reason: 'load 히트가 순서를 갱신하지 않았다');
  });

  test('load가 받아 온 바이트는 같은 상한 정책으로 캐시된다(배선)', () async {
    final storage = _FakeStorage((path) async => bytes(path.length));
    final loader = FirebaseBodyPhotoLoader(storage);
    for (var i = 0; i < FirebaseBodyPhotoLoader.maxEntries + 5; i++) {
      expect(await loader.load('p/$i.jpg'), isA<Ok<Uint8List>>());
    }
    final keys = FirebaseBodyPhotoLoader.debugCachedPaths();
    expect(keys, hasLength(FirebaseBodyPhotoLoader.maxEntries), reason: 'load 경로가 상한을 우회했다');
    expect(keys.first, 'p/5.jpg');
    expect(storage.calls, FirebaseBodyPhotoLoader.maxEntries + 5);
    await loader.load('p/${FirebaseBodyPhotoLoader.maxEntries + 4}.jpg');
    expect(storage.calls, FirebaseBodyPhotoLoader.maxEntries + 5, reason: '받아 둔 것을 다시 받았다 — load가 캐시에 넣지 않는다');
  });

  test('받는 도중 세션이 끝나면(clear) 늦게 온 바이트를 다음 세션 캐시에 남기지 않는다', () async {
    final gate = Completer<Uint8List?>();
    final loader = FirebaseBodyPhotoLoader(_FakeStorage((_) => gate.future));
    final pending = loader.load('members/A/body/a.jpg'); // A의 사진을 받는 중
    loader.clear(); // A 로그아웃(Session.clear) — B가 이어서 로그인한다
    gate.complete(bytes(1)); // 느린 망에서 A의 바이트가 이제 도착
    expect(await pending, isA<Ok<Uint8List>>(), reason: '요청한 쪽(사라지는 A의 화면)에는 그대로 돌려준다');
    expect(FirebaseBodyPhotoLoader.debugCachedPaths(), isEmpty,
        reason: '세션 경계를 넘은 민감정보가 B의 세션 캐시에 남았다');
    expect(loader.peek('members/A/body/a.jpg'), isNull);
  });

  test('clearCache는 전부 비운다(회원 전환 규약 유지)', () {
    FirebaseBodyPhotoLoader.debugPut('p/a.jpg', bytes(1));
    FirebaseBodyPhotoLoader.clearCache();
    expect(FirebaseBodyPhotoLoader.debugCachedPaths(), isEmpty);
  });
}
