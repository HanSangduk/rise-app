package api

// 자필 서명 캡처(P44, 계약 v2.21) 테스트. 축은 넷이다:
//
//  1. 두 해시 분리(P44 결정 3) — 서명 이미지가 내용 봉인(contractSeal)에 절대 새어들지 않는다.
//     같은 스탬프의 두 계약을 서명 유/무로 갈라 서명해도 내용 SHA256이 **동일 골든 hex**여야
//     한다(쌍 대조). 골든은 contract_template_test.go의 봉인 골든 벡터와 같은 입력·같은
//     독립 계산 hex다 — contractSeal 구현을 경유하지 않고 박은 값이라, 서명이 입력에 섞이는
//     뮤테이션은 여기서 죽는다.
//  2. 저장 정규형 — signature_png는 수신 문자열이 아니라 원본 바이트의 재인코딩 base64,
//     signature_sha256은 **원본 PNG 바이트**의 해시(base64 문자열의 해시가 아니라). 테스트가
//     구현이 아닌 정의(crypto/sha256 직접 호출)로 재계산해 대조한다.
//  3. 빈 값 신호(P44 결정 6) — 바디 없음·빈 바디·빈 문자열은 전부 구버전 클릭 동의 서명으로
//     성립하고, 두 서명 필드는 비어 있는 그대로다. mutate는 받지 않은 값을 쓰지 않는다
//     (잔존값 비클로버 — v2.18 스탬프 보존과 같은 철학).
//  4. 검증 게이트(400) — base64·PNG 매직·크기 상한·치수 위생이 서비스 호출 전에 자르고,
//     거부된 요청은 저장본을 1바이트도 건드리지 않는다. writeErr 매핑까지 라우터로 고정한다.

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// signPadPNG — w×h 실제 PNG(그레이스케일, 대각선 획)를 인코딩해 돌려준다. 매직·IHDR이
// 진짜여야 png.DecodeConfig 검증을 통과한다 — 손으로 박은 가짜 바이트 픽스처를 쓰지 않는다.
func signPadPNG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewGray(image.Rect(0, 0, w, h))
	for i := 0; i < w && i < h; i++ {
		img.SetGray(i, i, color.Gray{Y: 255})
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("png encode: %v", err)
	}
	return buf.Bytes()
}

// signPadPNGTruncated — IHDR 청크까지만 남기고 절단한 PNG(P44 마감 리뷰 픽스처).
// 매직 8B + IHDR 청크(길이4+타입4+데이터13+CRC4 = 25B) = 33B — DecodeConfig는 치수를
// 읽어내지만 IDAT·IEND가 없어 어떤 디코더로도 픽셀을 렌더할 수 없다.
func signPadPNGTruncated(t *testing.T) []byte {
	t.Helper()
	full := signPadPNG(t, 300, 120)
	return append([]byte{}, full[:33]...)
}

// oversizeSignaturePNG — 유효한 PNG의 IEND 뒤에 패딩을 붙여 64KB 상한만 초과시킨다.
// DecodeConfig는 헤더까지만 읽으므로 매직·치수 검증은 그대로 통과한다 — 이 픽스처가 400이
// 되는 이유가 "크기 상한" 하나로 고립된다(상한 제거 뮤턴트를 정확히 이것만으로 죽인다).
func oversizeSignaturePNG(t *testing.T) []byte {
	t.Helper()
	base := signPadPNG(t, 300, 120)
	return append(base, make([]byte, maxSignaturePNGBytes-len(base)+1)...)
}

// seedStampedSentContract — 골든 스탬프(pt-v1 + 골든 vars)가 앉은 sent 계약을 스토어 직행으로
// 심는다. 래치·조립 기계를 통째로 우회하는 이유: 이 파일의 관심사는 "서명 시점의 봉인·기록"
// 이지 스탬프 조립이 아니고(그건 service_contract_stamp_test.go), 두 계약의 스탬프를 **바이트
// 동일**하게 만들려면 조립 재료(회원명 등)가 끼어들면 안 된다.
func seedStampedSentContract(t *testing.T, s *Service, name, phone string) (memberID, contractID string) {
	t.Helper()
	mem := seedMemberOnly(t, s, name, phone)
	pass := seedBarePass(t, s, mem.ID, domain.PassStatusActive)
	cid, err := s.store.CreateContract(context.Background(), testCenter, &domain.Contract{
		MemberID: mem.ID, PassID: pass.ID, Status: domain.ContractStatusSent,
		TemplateVersion: "pt-v1",
		Vars:            map[string]string{"위약금율": "10", "상품명": "PT 10회", "계약금액": "1,000,000"},
	})
	if err != nil {
		t.Fatalf("CreateContract(스토어): %v", err)
	}
	return mem.ID, cid
}

// goldenStampSeal — 위 골든 vars에 대한 봉인 hex. contract_template_test.go의 골든 벡터와
// 같은 값(python hashlib 독립 계산, 2026-08-29) — contractSeal을 불러 만들지 않는다.
const goldenStampSeal = "09d9adf5497b6c9d9666b834cee087cbe02b28eb441c1264b96492f211727da6"

// 두 해시 분리의 쌍 대조(P44 결정 3): 같은 스탬프를 서명 이미지 유/무로 서명해도 내용 봉인은
// 같은 골든 hex다. 서명 이미지가 contractSeal 입력에 새어들면 유-서명 쪽 봉인이 골든에서
// 이탈해 즉사한다. 함께 고정: 서명 필드의 저장 정규형(재인코딩 base64 + 원본 바이트 해시)과
// 응답·저장본 일치, 무-서명 쪽 두 필드 공백.
func TestSignContractTwoHashSeparationPairedGolden(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	memA, cidA := seedStampedSentContract(t, s, "김민지", "010-1234-5678")
	memB, cidB := seedStampedSentContract(t, s, "이서준", "010-9999-0000")

	sig := signPadPNG(t, 300, 120)
	sum := sha256.Sum256(sig) // 정의로 재계산(구현 경유 없음) — 엉뚱한 바이트 해시 뮤턴트 검출
	wantSigHash := hex.EncodeToString(sum[:])
	wantSigB64 := base64.StdEncoding.EncodeToString(sig)

	withSig, err := s.SignContract(ctx, memberP(memA), cidA, "1.2.3.4", sig)
	if err != nil {
		t.Fatalf("서명(이미지 포함): %v", err)
	}
	if withSig.SignaturePNG != wantSigB64 {
		t.Errorf("signature_png가 원본 바이트의 정규 base64가 아니다(len %d, want %d)",
			len(withSig.SignaturePNG), len(wantSigB64))
	}
	if withSig.SignatureSHA256 != wantSigHash {
		t.Errorf("signature_sha256 = %q, want 원본 PNG 바이트의 해시 %q", withSig.SignatureSHA256, wantSigHash)
	}
	if withSig.SHA256 != goldenStampSeal {
		t.Errorf("내용 봉인 = %q, want 골든 %q — 서명 이미지가 contractSeal 입력에 샜다(P44 결정 3 위반)",
			withSig.SHA256, goldenStampSeal)
	}
	savedA, err := s.store.GetContract(ctx, testCenter, cidA)
	if err != nil {
		t.Fatal(err)
	}
	if savedA.SignaturePNG != wantSigB64 || savedA.SignatureSHA256 != wantSigHash || savedA.SHA256 != goldenStampSeal {
		t.Errorf("저장본이 응답과 다르다: sig_len=%d hash=%q seal=%q",
			len(savedA.SignaturePNG), savedA.SignatureSHA256, savedA.SHA256)
	}

	without, err := s.SignContract(ctx, memberP(memB), cidB, "5.6.7.8", nil)
	if err != nil {
		t.Fatalf("서명(이미지 없음): %v", err)
	}
	if without.SignaturePNG != "" || without.SignatureSHA256 != "" {
		t.Errorf("무-서명인데 서명 필드가 찼다: png_len=%d hash=%q — 빈 값 ⟺ 체크 동의만(P44 결정 6)",
			len(without.SignaturePNG), without.SignatureSHA256)
	}
	if without.SHA256 != goldenStampSeal {
		t.Errorf("무-서명 봉인 = %q, want 골든 %q", without.SHA256, goldenStampSeal)
	}
	// 명시적 쌍 대조 — 이 한 줄이 두 해시 분리의 뮤테이션 가드다.
	if withSig.SHA256 != without.SHA256 {
		t.Errorf("서명 유/무가 내용 봉인을 갈랐다: %q vs %q — 서명은 내용의 일부가 아니다", withSig.SHA256, without.SHA256)
	}
}

// mutate는 받지 않은 값을 쓰지 않는다: 서명 필드가 이미 앉아 있는 sent 잔존 상태(손시딩·
// 마이그레이션 잔재 — 정상 플로우로는 못 만든다)에서 무-서명 sign이 그 값을 지우면 안 된다.
// "항상 재할당" 뮤턴트(빈 문자열 덮어쓰기)는 이 관측에서만 구분되고 여기서 죽는다.
func TestSignContractWithoutSignatureLeavesResidualUntouched(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedMemberOnly(t, s, "김민지", "010-1234-5678")
	pass := seedBarePass(t, s, mem.ID, domain.PassStatusActive)
	cid, err := s.store.CreateContract(ctx, testCenter, &domain.Contract{
		MemberID: mem.ID, PassID: pass.ID, Status: domain.ContractStatusSent,
		SignaturePNG: "aWNvbg==", SignatureSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil); err != nil {
		t.Fatalf("서명: %v", err)
	}
	saved, err := s.store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.SignaturePNG != "aWNvbg==" || saved.SignatureSHA256 == "" {
		t.Errorf("무-서명 sign이 잔존 서명 필드를 덮었다: png=%q hash=%q — 받지 않은 값은 쓰지 않는다",
			saved.SignaturePNG, saved.SignatureSHA256)
	}
}

// newContractSignRouter — 라우터와 서비스를 같은 스토어로 함께(newBusinessTestRouter와 같은
// 이유 — 픽스처는 서비스로 심고 검사는 HTTP로). member 인증은 UserIndex 시딩으로 잇는다.
func newContractSignRouter(t *testing.T) (http.Handler, *Service) {
	t.Helper()
	svc := newTestService()
	auth, err := NewAuthenticator(context.Background(), svc.cfg, svc.store)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}
	return NewRouter(NewHandlers(svc), auth, nil), svc
}

// seedWireSignContract — HTTP 경유 서명 테스트용 픽스처: 회원 + 활성 패스 + sent 계약 +
// dev uid를 회원으로 잇는 UserIndex. 반환은 (dev uid, 계약 id).
func seedWireSignContract(t *testing.T, svc *Service, name, phone string) (uid, cid string) {
	t.Helper()
	mem := seedMemberOnly(t, svc, name, phone)
	pass := seedBarePass(t, svc, mem.ID, domain.PassStatusActive)
	id, err := svc.store.CreateContract(context.Background(), testCenter, &domain.Contract{
		MemberID: mem.ID, PassID: pass.ID, Status: domain.ContractStatusSent,
	})
	if err != nil {
		t.Fatal(err)
	}
	uid = "u-" + mem.ID
	if err := svc.store.SaveUserIndex(context.Background(), &store.UserIndex{
		UID: uid, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID,
	}); err != nil {
		t.Fatal(err)
	}
	return uid, id
}

// 와이어 핀(P44 결정 6): 바디 없음·빈 JSON·빈 문자열 전부 200 서명 성립(구버전 앱 그대로 유효),
// 서명 이미지 첨부는 200 + 두 필드 기록. 응답 JSON에 두 키가 **항상 존재**한다(omitempty 금지
// — 앱이 키 부재/빈 값을 구분할 일이 없어야 한다).
func TestSignContractWireLegacyAndSignature(t *testing.T) {
	r, svc := newContractSignRouter(t)

	post := func(uid, cid, body string) (*domain.Contract, map[string]json.RawMessage, int) {
		t.Helper()
		rec := postJSON(t, r, "/v1/contracts/"+cid+"/sign", uid, domain.RoleMember, body)
		var c domain.Contract
		var keys map[string]json.RawMessage
		if rec.Code == http.StatusOK {
			if err := json.Unmarshal(rec.Body.Bytes(), &c); err != nil {
				t.Fatalf("응답 파싱: %v", err)
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &keys); err != nil {
				t.Fatal(err)
			}
		}
		return &c, keys, rec.Code
	}

	// ① 바디 없음 — 구버전 앱의 요청 그대로.
	uid1, cid1 := seedWireSignContract(t, svc, "김민지", "010-1111-0001")
	c1, keys1, code := post(uid1, cid1, "")
	if code != http.StatusOK || c1.Status != domain.ContractStatusSigned {
		t.Fatalf("바디 없는 서명 = %d(%s), want 200 signed — 구버전 호환 파괴(P44 결정 6)", code, c1.Status)
	}
	if c1.SignaturePNG != "" || c1.SignatureSHA256 != "" {
		t.Errorf("바디 없는 서명에 서명 필드가 찼다: %q %q", c1.SignaturePNG, c1.SignatureSHA256)
	}
	for _, k := range []string{"signature_png", "signature_sha256"} {
		if _, ok := keys1[k]; !ok {
			t.Errorf("응답 JSON에 %s 키가 없다 — omitempty 금지 규약(통문서 Set 무손실) 위반", k)
		}
	}

	// ② 빈 JSON / 빈 문자열 — 같은 신호의 다른 표기.
	uid2, cid2 := seedWireSignContract(t, svc, "이서준", "010-1111-0002")
	if _, _, code := post(uid2, cid2, `{}`); code != http.StatusOK {
		t.Errorf("빈 JSON 서명 = %d, want 200", code)
	}
	uid3, cid3 := seedWireSignContract(t, svc, "박지후", "010-1111-0003")
	if c3, _, code := post(uid3, cid3, `{"signature_png":""}`); code != http.StatusOK || c3.SignaturePNG != "" {
		t.Errorf("빈 문자열 서명 = %d(png=%q), want 200 + 공백 유지", code, c3.SignaturePNG)
	}

	// ③ 서명 이미지 첨부.
	uid4, cid4 := seedWireSignContract(t, svc, "최유나", "010-1111-0004")
	sig := signPadPNG(t, 300, 120)
	b64 := base64.StdEncoding.EncodeToString(sig)
	c4, _, code := post(uid4, cid4, `{"signature_png":"`+b64+`"}`)
	if code != http.StatusOK {
		t.Fatalf("서명 이미지 첨부 = %d, want 200", code)
	}
	sum := sha256.Sum256(sig)
	if c4.SignaturePNG != b64 || c4.SignatureSHA256 != hex.EncodeToString(sum[:]) {
		t.Errorf("응답 서명 필드 불일치: png_len=%d hash=%q", len(c4.SignaturePNG), c4.SignatureSHA256)
	}
	saved, err := svc.store.GetContract(context.Background(), testCenter, cid4)
	if err != nil {
		t.Fatal(err)
	}
	if saved.SignaturePNG != b64 || saved.SignatureSHA256 != c4.SignatureSHA256 {
		t.Errorf("저장본 서명 필드가 응답과 다르다")
	}
}

// 검증 게이트(400) 테이블: 각 거부 후 계약은 sent 그대로, 서명 흔적 0바이트. 매직 실패와
// 헤더 손상의 **문구가 다르다**는 것까지 고정한다 — 선분리 매직 검사가 DecodeConfig에 흡수되는
// 뮤테이션(검사 삭제)은 JPEG 케이스의 문구 이탈로 죽는다.
func TestSignContractWireValidationRejects(t *testing.T) {
	r, svc := newContractSignRouter(t)
	uid, cid := seedWireSignContract(t, svc, "김민지", "010-2222-0001")

	b64 := func(b []byte) string { return base64.StdEncoding.EncodeToString(b) }
	cases := []struct {
		name, body, wantMsg string
	}{
		{"base64 아님", `{"signature_png":"!!!not-base64!!!"}`, "base64"},
		{"PNG 아님(JPEG 매직)", `{"signature_png":"` + b64([]byte{0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4}) + `"}`, "PNG 형식"},
		// 깨진 헤더에도 유효 IEND 접미를 붙인다 — P44 마감 리뷰의 접미 검사가 먼저 잡아버리면
		// 이 행이 지키려던 DecodeConfig 층(IHDR 해석) 검증이 공허해진다. 층별로 한 행씩.
		{"PNG 매직 + 깨진 헤더(IEND는 정상)", `{"signature_png":"` + b64(append(append(append([]byte{}, pngMagic...), []byte("garbage")...), pngIENDSuffix...)) + `"}`, "해석할 수 없어요"},
		// P44 마감 리뷰: DecodeConfig는 IHDR만 읽는다 — IHDR 뒤를 잘라낸 "렌더 불가 PNG"가
		// 증거로 저장되던 갭. IEND 접미 검사가 잡는다(IEND 뒤 쓰레기도 같은 검사가 차단).
		{"절단 PNG(IHDR까지만, IEND 없음)", `{"signature_png":"` + b64(signPadPNGTruncated(t)) + `"}`, "손상됐어요"},
		{"IEND 뒤 쓰레기", `{"signature_png":"` + b64(append(append([]byte{}, signPadPNG(t, 300, 120)...), []byte("junk")...)) + `"}`, "손상됐어요"},
		{"크기 상한 초과", `{"signature_png":"` + b64(oversizeSignaturePNG(t)) + `"}`, "너무 커요"},
		{"치수 미달(10×10)", `{"signature_png":"` + b64(signPadPNG(t, 10, 10)) + `"}`, "크기가 올바르지 않아요"},
		{"치수 초과(2200×100)", `{"signature_png":"` + b64(signPadPNG(t, 2200, 100)) + `"}`, "크기가 올바르지 않아요"},
		{"미지 필드", `{"signature":"x"}`, "지원하지 않는 필드"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := postJSON(t, r, "/v1/contracts/"+cid+"/sign", uid, domain.RoleMember, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", rec.Code)
			}
			var eb struct {
				Error string `json:"error"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &eb); err != nil {
				t.Fatal(err)
			}
			if !bytes.Contains([]byte(eb.Error), []byte(tc.wantMsg)) {
				t.Errorf("error = %q, want %q 포함", eb.Error, tc.wantMsg)
			}
		})
	}
	// 거부 연타 후에도 저장본은 발송 직후 그대로다.
	saved, err := svc.store.GetContract(context.Background(), testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSent || saved.SignedAt != nil ||
		saved.SignaturePNG != "" || saved.SignatureSHA256 != "" {
		t.Errorf("거부된 요청이 저장본을 건드렸다: %s(signed_at=%v, png_len=%d, hash=%q)",
			saved.Status, saved.SignedAt, len(saved.SignaturePNG), saved.SignatureSHA256)
	}
}
