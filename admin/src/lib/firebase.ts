// Firebase 웹 SDK 초기화(P06) — rize-218c1 프로젝트, modular API(v12).
// 웹 config는 비밀이 아니라 "식별자"다(Firebase 공식 문서 명시) — 하드코딩해도 무방하며,
// 실제 보안 경계는 백엔드의 ID 토큰 검증(Authorization: Bearer)과 Firebase 콘솔 설정이 담당한다.
import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getStorage } from "firebase/storage";

const app = initializeApp({
  apiKey: "AIzaSyBA3GAC9tHW7ELnhBTSlrDP_gQeHS2H3ec",
  authDomain: "rize-218c1.firebaseapp.com",
  projectId: "rize-218c1",
  storageBucket: "rize-218c1.firebasestorage.app",
  messagingSenderId: "773077624928",
  appId: "1:773077624928:web:88a62ec6adb78e91b0fb05",
});

// 이메일/비밀번호 로그인(콘솔에서 활성화 완료) — 세션은 기본 persistence(IndexedDB)로
// 새로고침을 넘어 유지되고, auth.tsx의 onAuthStateChanged 구독이 복원을 감지한다.
export const auth = getAuth(app);

// 체형사진 열람용(P21). **getDownloadURL은 쓰지 않는다** — 그 토큰 URL은 Storage 규칙을
// 거치지 않는 무기한 열쇠라, 동의를 철회한 회원의 사진이 계속 열린다. getBlob으로 매번
// 규칙 평가를 지나게 한다(앱도 같은 이유로 getData만 쓴다).
export const storage = getStorage(app);
