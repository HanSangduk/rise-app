// Firebase Auth 오류 코드 → 한국어 (P73 — Login.tsx의 표를 공용화).
//
// 종전엔 이 표가 로그인 화면 안에만 있었고, 같은 SDK 호출(sendPasswordResetEmail)을 하는
// 트레이너 초대(Settings.tsx)·새 센터 등록(Centers.tsx)의 "메일 발송 실패" 안내는 `e.code`를
// 그대로 문장에 꽂았다 — "발송 실패 사유: auth/network-request-failed" 처럼 대표가 읽을 수 없는
// 영문 enum이 한국어 문장 한가운데 떴다(P50이 결함 클래스로 규정한 바로 그 모양).
//
// 이 표의 원칙(로그인 화면에서 세운 것 그대로): "관리자에게 문의하세요"라고 쓰지 않는다. 이
// 제품에 관리자는 없다 — 최상위 사용자가 센터 대표 본인이라, 문의하라는 말은 아무 데도 가지 않는
// 막다른 길이다. 제품 안에 해결 경로가 있으면 그 경로를, 없으면 없다는 사실을 그대로 쓴다.
import { FirebaseError } from "firebase/app";

// invalid-credential은 이메일 열거 보호(기본 ON)로 "없는 계정"과 "비번 틀림"을 구분해주지
// 않는다 — 메시지도 묶어서 안내한다.
export const FB_ERROR_KO: Record<string, string> = {
  "auth/invalid-credential": "이메일 또는 비밀번호가 맞지 않아요",
  "auth/user-not-found": "이메일 또는 비밀번호가 맞지 않아요",
  "auth/wrong-password": "이메일 또는 비밀번호가 맞지 않아요",
  "auth/invalid-email": "이메일 형식이 올바르지 않아요",
  // 퇴사 처리가 Firebase 계정을 잠그므로 일상적으로 도달하는 상태다(설정·직원 → 퇴사).
  // 되돌리는 실물 버튼이 제품 안에 있다: [설정 · 직원] 직원 표의 "재입사" → 재입사 처리.
  "auth/user-disabled":
    "퇴사 처리된 계정이에요 — 센터 대표가 [설정 · 직원]에서 재입사 처리하면 다시 로그인할 수 있어요",
  "auth/too-many-requests": "로그인 시도가 너무 많았어요 — 잠시 후 다시 시도해주세요",
  // api.ts의 오프라인 문구와 같은 말로 맞춘다 — 같은 사고(와이파이 끊김)를 화면마다
  // 다른 말로 부르면 대표는 서로 다른 문제로 읽는다.
  "auth/network-request-failed": "인터넷 연결이 끊긴 것 같아요 — 연결을 확인하고 다시 시도해주세요",
  // 이건 센터에서 손댈 수 있는 스위치가 아니다(Firebase 콘솔 설정). 고칠 수 없는 일을
  // "문의하세요"로 떠넘기지 말고, 센터 밖 문제라는 사실을 그대로 알린다.
  "auth/operation-not-allowed":
    "이메일 로그인이 꺼져 있어요 — 센터에서 켤 수 있는 설정이 아니라 PT데스크에 알려야 해요",
};

/** 로그인 실패 → 한국어 한 줄. 표에 없는 코드·Firebase 밖 예외는 고정 문구, 원문은 콘솔로. */
export function loginErrorKo(e: unknown): string {
  // 표에 없는 코드(auth/internal-error 등)와 Firebase 밖 예외(브라우저 영문 메시지)를
  // 그대로 흘리면 로그인 카드에 생 enum·영문이 찍힌다 — 대표에게는 읽을 수 없는 글자다.
  if (e instanceof FirebaseError) {
    const known = FB_ERROR_KO[e.code];
    if (known) return known;
    console.error("[login] 매핑되지 않은 Firebase 오류:", e.code, e);
  } else {
    console.error("[login] 로그인 중 예외:", e);
  }
  return "로그인에 실패했어요 — 잠시 후 다시 시도해주세요";
}

// 비밀번호 설정 메일(sendPasswordResetEmail) 실패 → 한국어 한 줄.
//
// 로그인 표와 다른 점: 여기서 "이메일 또는 비밀번호가 맞지 않아요"는 거짓이다(비밀번호를 보낸
// 적이 없다). 메일 경로에서 실제로 뜨는 코드만 따로 적고, 나머지는 로그인 표를 재사용한다.
const MAIL_ERROR_KO: Record<string, string> = {
  "auth/invalid-email": "이메일 형식이 올바르지 않아 메일을 보낼 수 없었어요",
  // 계정은 서버가 방금 만들었으므로 정상 흐름에선 나오지 않는다 — 나온다면 프로젝트가 다른 것.
  "auth/user-not-found": "메일을 보낼 계정을 찾지 못했어요(어드민이 다른 Firebase 프로젝트를 보고 있을 수 있어요)",
  "auth/too-many-requests": "메일 발송 요청이 너무 잦았어요 — 잠시 후 로그인 화면의 \"비밀번호를 잊으셨나요\"로 다시 받을 수 있어요",
  "auth/network-request-failed": "인터넷 연결이 끊긴 것 같아요 — 연결을 확인해주세요",
  "auth/missing-continue-uri": "메일 설정이 올바르지 않아요 — 센터에서 고칠 수 있는 설정이 아니라 PT데스크에 알려야 해요",
  "auth/unauthorized-continue-uri": "메일 설정이 올바르지 않아요 — 센터에서 고칠 수 있는 설정이 아니라 PT데스크에 알려야 해요",
};

/**
 * 메일 발송 실패 → 한국어 한 줄. 표에 없는 Firebase 코드는 "코드: auth/…" 형태로 **뒤에** 붙인다 —
 * 대표가 그대로 전달할 수 있는 식별자는 필요하지만, 문장의 주어 자리를 영문 enum이 차지하면 안 된다.
 */
export function mailErrorKo(e: unknown): string {
  if (e instanceof FirebaseError) {
    const known = MAIL_ERROR_KO[e.code];
    if (known) return known;
    console.error("[mail] 매핑되지 않은 Firebase 오류:", e.code, e);
    return `메일 서버가 요청을 거절했어요 (코드: ${e.code})`;
  }
  console.error("[mail] 메일 발송 중 예외:", e);
  return "메일을 보내는 중 알 수 없는 문제가 있었어요";
}
