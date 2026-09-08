package api

// 재등록/상담 요청(계약 v2.20, P42) — 회원발 요청 큐. JoinRequest(가입 요청)와 같은 패턴:
// 회원이 손들면 데스크가 보고 처리한다. 결제·발급은 여기서 일어나지 않는다 — 처리의 실체는
// 어드민의 기존 수기 플로우(회원권 발급+결제 기록)이고, 이 큐는 그 앞의 손잡이다.

import (
	"context"
	"errors"
	"unicode/utf8"

	"github.com/ramsang/rise-backend/internal/store"
)

// consultNoteMaxRunes — 한 줄 메모 상한. 상담 내용이 아니라 "왜 손들었는지" 힌트다 —
// 긴 사연은 데스크 상담(전화·대면)의 몫이라 폼을 그쪽으로 키우지 않는다.
const consultNoteMaxRunes = 200

// ConsultRequestBody — POST /v1/consult-requests {kind, note?}.
type ConsultRequestBody struct {
	Kind string `json:"kind"`
	Note string `json:"note"`
}

// ConsultRequestView — 목록 응답: 요청 + 회원 이름. 어드민 "해야 할 일"이 이름 없이 member_id만
// 받으면 회원마다 재조회하게 된다(JoinRequest가 Name을 품는 것과 같은 이유 — 다만 이쪽은
// 기존 회원이라 저장하지 않고 응답에서 해석한다: 개명·정정이 목록에 즉시 반영).
type ConsultRequestView struct {
	store.ConsultRequest
	MemberName string `json:"member_name"`
}

// CreateConsultRequest — 회원 본인 전용. pending 중복은 409 — 연타·불안 재전송으로 데스크 큐가
// 같은 사람으로 쌓이지 않게 한다(요청이 살아 있다는 사실 자체가 응답으로 전달된다).
func (s *Service) CreateConsultRequest(ctx context.Context, p Principal, req ConsultRequestBody) (*store.ConsultRequest, error) {
	if !p.IsMember() || p.MemberID == "" {
		// 매칭 전(멤버 미연결) 계정은 재등록을 요청할 대상 자체가 없다 — 가입 요청이 먼저다.
		return nil, ErrForbidden
	}
	if req.Kind != store.ConsultKindRenewal && req.Kind != store.ConsultKindConsult {
		return nil, errors.Join(errBadRequest, errors.New("요청 종류가 올바르지 않아요"))
	}
	if utf8.RuneCountInString(req.Note) > consultNoteMaxRunes {
		return nil, errors.Join(errBadRequest, errors.New("메모는 200자 이내로 적어주세요"))
	}
	existing, err := s.store.ListConsultRequests(ctx, p.CenterID, p.MemberID)
	if err != nil {
		return nil, err
	}
	for _, cr := range existing {
		if cr.Status == store.ConsultPending {
			return nil, errors.Join(ErrConflict,
				errors.New("이미 보낸 요청이 있어요 — 센터에서 곧 연락드릴 거예요"))
		}
	}
	cr := &store.ConsultRequest{MemberID: p.MemberID, Kind: req.Kind, Note: req.Note, Status: store.ConsultPending}
	id, err := s.store.CreateConsultRequest(ctx, p.CenterID, cr)
	if err != nil {
		return nil, err
	}
	cr.ID = id
	return cr, nil
}

// ListConsultRequests — 역할별 스코프가 다르다:
//   - member: **자기 것만**(이름 해석 불필요 — 앱이 "요청 보냈어요" 상태를 복원하는 용도).
//   - owner: 센터 전체. trainer: **담당 회원 것만**(ListMembers·수업기록과 같은 P37 스코프 경계).
func (s *Service) ListConsultRequests(ctx context.Context, p Principal) ([]ConsultRequestView, error) {
	if p.IsMember() {
		if p.MemberID == "" {
			return []ConsultRequestView{}, nil // 매칭 전 — 요청이 존재할 수 없다
		}
		list, err := s.store.ListConsultRequests(ctx, p.CenterID, p.MemberID)
		if err != nil {
			return nil, err
		}
		out := make([]ConsultRequestView, 0, len(list))
		for _, cr := range list {
			out = append(out, ConsultRequestView{ConsultRequest: cr})
		}
		return out, nil
	}
	if !p.IsStaff() {
		return nil, ErrForbidden
	}
	list, err := s.store.ListConsultRequests(ctx, p.CenterID, "")
	if err != nil {
		return nil, err
	}
	out := make([]ConsultRequestView, 0, len(list))
	for _, cr := range list {
		mem, err := s.store.GetMember(ctx, p.CenterID, cr.MemberID)
		if err != nil {
			if errors.Is(err, store.ErrNotFound) {
				// 탈퇴 등으로 회원 문서가 사라져도 큐를 죽이지 않는다 — 이름 없이 내려보내면
				// owner가 판단할 수 있고, trainer 스코프는 판정 불가라 제외(fail-closed).
				if p.IsOwner() {
					out = append(out, ConsultRequestView{ConsultRequest: cr})
				}
				continue
			}
			return nil, err
		}
		if p.IsTrainer() && mem.TrainerID != p.UID {
			continue
		}
		out = append(out, ConsultRequestView{ConsultRequest: cr, MemberName: mem.Name})
	}
	return out, nil
}

// DoneConsultRequest — POST /v1/consult-requests/{id}/done(스태프). 데스크가 상담을 마치고
// 큐에서 내리는 동사 — 발급·결제와 묶지 않는다(요청이 "상담했지만 미등록"으로 끝나는 것도
// 정상 결말이라서).
//
// **done → done은 멱등이다**(에러 아님): 두 스태프가 같은 요청을 나눠 처리하는 게 데스크의
// 실제 동선이고, 두 번째 누름이 409로 튀면 "처리 안 된 건가"라는 헛확인이 생긴다.
// JoinApprove가 중복을 409로 막는 것과 다른 이유: 그쪽은 두 번째 누름이 **회원 레코드를
// 하나 더 만들기** 때문이고, 여기는 상태 표식 하나라 결과가 같다.
func (s *Service) DoneConsultRequest(ctx context.Context, p Principal, id string) (*store.ConsultRequest, error) {
	if !p.IsStaff() {
		return nil, ErrForbidden
	}
	cr, err := s.store.GetConsultRequest(ctx, p.CenterID, id)
	if err != nil {
		return nil, err
	}
	if p.IsTrainer() {
		mem, err := s.store.GetMember(ctx, p.CenterID, cr.MemberID)
		if err != nil {
			return nil, err // 회원 문서가 없으면 trainer는 담당 판정 불가 — owner 몫(fail-closed)
		}
		if mem.TrainerID != p.UID {
			return nil, ErrForbidden
		}
	}
	if cr.Status == store.ConsultDone {
		return cr, nil
	}
	cr.Status = store.ConsultDone
	// **note를 비운다**(v2.28, P56 A5) — JoinReject·JoinApprove가 이름·번호를 비우는 것과 같은
	// 판단이다. note는 회원이 직접 쓴 자유 서술이라 무엇이 적혔는지 서버가 알 수 없고("무릎이
	// 아파서" 같은 건강 정보가 실제로 들어온다 — P53), 그 처리 목적은 데스크가 상담을 마치는
	// 순간 끝난다. P53이 이 큐를 5년 보존 대상이 아니라고 판정한 근거 그대로다: 여기서는
	// 결제·발급이 일어나지 않고, 상담 후 남는 실제 사업 기록(Pass·Payment·Contract)은 따로
	// 5년 보존된다. done 이후 note를 읽는 화면도 없다 — 어드민 "해야 할 일"은 pending을 위한
	// 것이고, 회원 앱은 status로 "요청 보냈어요"를 복원할 뿐이다.
	//
	// 행은 남긴다(status·created_at·member_id·kind): 멱등(done→done)과 "요청이 있었다"는 사실이
	// 그것으로 완결된다. 탈퇴 시엔 P53의 스윕이 행째 지운다 — 그쪽이 문서를 지우고 이쪽이 내용을
	// 비우는 것은 JoinReject와 DeleteJoinRequestsByUID의 관계와 같다.
	cr.Note = ""
	if err := s.store.UpdateConsultRequest(ctx, p.CenterID, cr); err != nil {
		return nil, err
	}
	return cr, nil
}
