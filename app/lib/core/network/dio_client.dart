import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/network/api_config.dart';
import 'package:rise_member/core/network/dev_session.dart';
import 'package:rise_member/core/session/session_provider.dart';

part 'dio_client.g.dart';

/// 공용 Dio 클라이언트 — 인증 헤더 인터셉터 포함.
/// dev 모드: `X-Dev-Role` / `X-Dev-Uid`. 운영: `Authorization: Bearer <Firebase ID token>`.
@riverpod
Dio dio(Ref ref) {
  final devSession = ref.watch(devSessionProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(milliseconds: ApiConfig.connectTimeoutMs),
      receiveTimeout: const Duration(milliseconds: ApiConfig.receiveTimeoutMs),
      contentType: 'application/json',
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      // 401 = 신원이 사라졌다(토큰 폐기·계정 삭제·다른 기기에서 탈퇴).
      // **여기서 세션을 비운다** — 라우터가 세션을 보고 로그인으로 되돌린다.
      //
      // 403은 건드리지 않는다: 신원은 멀쩡한데 권한이 없다는 뜻이라(담당 아닌 코치,
      // 탈퇴 회원의 잔여 호출) 그걸로 로그아웃시키면 정상 거절이 세션 종료로 번진다.
      //
      // 토큰 갱신 자체는 Firebase SDK가 한다(`getIdToken()`은 만료가 임박하면 알아서
      // 새로 받아온다) — 여기까지 401이 왔다는 건 갱신으로 살릴 수 없는 상태다.
      onError: (e, handler) {
        if (e.response?.statusCode == 401) {
          ref.read(sessionProvider.notifier).clear();
        }
        handler.next(e);
      },
      onRequest: (options, handler) async {
        // 인증 이중화(P06 마이그레이션 안전장치): Firebase 로그인 상태면 Bearer를
        // 항상 첨부하고, dev 헤더도 기존대로 유지 — 둘 다 와도 백엔드가 모드별로
        // 하나만 사용한다. 토큰 획득 실패(미초기화/미로그인/갱신 오류)는 조용히
        // 스킵해 dev 백엔드 흐름을 막지 않는다.
        try {
          final token = await FirebaseAuth.instance.currentUser?.getIdToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (_) {
          // Firebase 미초기화(테스트)·토큰 갱신 실패 — dev 헤더 경로로 계속.
        }
        if (devSession.enabled) {
          options.headers['X-Dev-Role'] = DevSession.role;
          options.headers['X-Dev-Uid'] = devSession.uid;
        }
        handler.next(options);
      },
    ),
  );

  return dio;
}
