import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:rise_member/core/network/api_config.dart';
import 'package:rise_member/core/result/retry_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/app.dart';
import 'package:rise_member/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 릴리스 빌드가 로컬 주소를 들고 나가면 여기서 멈춘다 — 설치되고 실행된 뒤
  // 모든 요청이 조용히 실패하는 것보다, 빌드 검증 단계에서 터지는 게 낫다.
  ApiConfig.assertConfiguredForRelease();
  // Firebase 초기화는 main에만 둔다 — 도메인/위젯 테스트가 Firebase 없이 돌게.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // ProviderScope = Riverpod 루트(= DI 컨테이너). get_it 미사용.
  // retry: 기본 정책은 도메인 Failure까지 10번 재시도해 "회원권 없음"이 뜨기까지
  // 38초가 걸렸다 — 근거와 판단 기준은 [appRetry] 주석.
  runApp(const ProviderScope(retry: appRetry, child: RiseMemberApp()));
}
