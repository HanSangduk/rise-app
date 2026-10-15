// 센터 관리(멀티센터 Phase B) — **superadmin 전용 화면**.
//
// 이 화면이 닫는 것은 하나다: 종전에 새 센터를 여는 유일한 방법이 **Firestore 콘솔에서 문서를
// 손으로 만드는 것**이었다(backend/README.md "남은 수작업"). 백엔드 관리 평면(계약 v2.16)은
// 이미 `POST /v1/admin/centers`로 센터 신원 + 기본 정책 + **최초 owner**를 한 요청에 만들 수
// 있는데, 그걸 부를 화면이 없었다.
//
// ## 왜 owner를 같은 폼에서 받나
//
// 닭-달걀 때문이다. 스태프 초대(`POST /v1/staff`)는 **그 센터의 owner만** 부를 수 있어서,
// owner가 없는 새 센터에는 아무도 초대할 수 없다. 그래서 센터 생성이 최초 owner까지 함께
// 만든다(서버가 role을 owner로 강제한다 — 최초 스태프가 trainer면 그 센터는 관리자 없는 방이 된다).
//
// ## 상호 미등록 센터가 목록에 어떻게 보이나 (v2.35, P70)
//
// v2.34까지 `GET /v1/admin/centers`는 **상호가 등록된 문서만** 돌려줬고, 1호 고객 라이즈가 상호
// 미등록이라 이 화면 첫 인상이 "등록된 센터가 없습니다"였다(각주로 설명하고 넘겼던 결정 — 람이
// 실제로 "라이즈 센터 있잖아"로 읽었다). v2.35부터 서버가 **기본 센터를 상호 없이도 항상 맨 앞에**
// 싣는다(회원용 목록 v2.33과 같은 집합). 상호가 빈 항목은 이름 자리에 "상호 미등록" 배지를 그리고,
// 상호를 채우는 곳(그 센터 대표의 설정 → 센터 신원)을 각주가 가리킨다. 기본 센터가 아닌 상호
// 미등록 문서(정책 지연 시딩·헬스체크가 만든 유령)는 여전히 오르지 않는다.

import { useState } from "react";
import { Building2, Plus } from "lucide-react";
import { sendPasswordResetEmail } from "firebase/auth";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  ErrorState,
  Input,
  Label,
  Modal,
  Spinner,
  TD,
  TH,
  THead,
  TR,
  Table,
} from "../components/ui";
import { auth } from "../lib/firebase";
import { mailErrorKo } from "../lib/firebaseErrorKo";
import { InitialPasswordNotice } from "./InitialPasswordNotice";
import { useAdminCenters, useCreateCenter } from "../lib/queries";
import { CENTER_ID_PATTERN, type CenterCreated } from "../lib/types";

// Go의 time.Time 제로값은 "0001-01-01T00:00:00Z"로 직렬화된다 — 지연 시딩으로만 존재해 온
// 기본 센터(신원 미등록)가 그 값을 싣고 오므로, 날짜처럼 그리면 "1년 1월 1일 등록"이 된다.
function formatCreated(iso: string | undefined): string {
  if (!iso || iso.startsWith("0001-")) return "—";
  return iso.slice(0, 10);
}

export function Centers() {
  const centers = useAdminCenters();
  const [open, setOpen] = useState(false);
  const [created, setCreated] = useState<CenterCreated | null>(null);
  // 대표 이메일은 **서버 응답에 없다**(domain.Staff에 email 필드가 없어 계정 발급 후 버려진다).
  // 그래서 폼이 알고 있는 값을 위로 올려 받는다 — 로그인 ID라 화면에서 사라지면 안 된다.
  const [createdOwnerEmail, setCreatedOwnerEmail] = useState("");
  // 비밀번호 설정 메일 발송 결과. null=아직/해당없음, ""=성공, 그 외=실패 사유(v2.36).
  // 계정 생성과 **분리해서** 들고 있는 이유는 트레이너 초대(Settings.tsx InviteStaffModal)가
  // 세운 규약과 같다: 메일 실패는 초대 실패가 아니다 — 계정은 이미 만들어졌고, 화면이 그
  // 사실과 대안(구두 전달)을 함께 말해야 한다.
  const [mailError, setMailError] = useState<string | null>(null);

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex items-center justify-between gap-3">
          <CardTitle>센터</CardTitle>
          <Button onClick={() => setOpen(true)}>
            <Plus className="mr-1.5 h-4 w-4" />새 센터 등록
          </Button>
        </CardHeader>
        <CardContent>
          {centers.isPending ? (
            <Spinner label="센터를 불러오는 중" />
          ) : centers.isError ? (
            <ErrorState error={centers.error} onRetry={() => centers.refetch()} />
          ) : centers.data && centers.data.length > 0 ? (
            <Table>
              <THead>
                <TR>
                  <TH>센터</TH>
                  <TH>ID</TH>
                  <TH>연락처</TH>
                  <TH>등록일</TH>
                </TR>
              </THead>
              <tbody>
                {centers.data.map((c) => (
                  <TR key={c.id}>
                    <TD>
                      <div className="flex items-center gap-2">
                        <Building2 className="h-4 w-4 shrink-0 text-muted" />
                        {c.name ? (
                          <span className="font-bold text-ink">{c.name}</span>
                        ) : (
                          <>
                            {/* 상호가 비면 ID를 이름 자리에 — 빈 칸은 "센터가 깨졌다"로 읽힌다. */}
                            <span className="font-mono font-bold text-ink">{c.id}</span>
                            <Badge tone="warn">상호 미등록</Badge>
                          </>
                        )}
                        {c.status !== "active" && <Badge tone="warn">{c.status}</Badge>}
                      </div>
                      {c.address && <div className="mt-0.5 text-[12px] text-muted">{c.address}</div>}
                    </TD>
                    <TD className="font-mono text-[12.5px] text-muted">{c.id}</TD>
                    <TD className="text-muted">{c.phone || "—"}</TD>
                    {/* RFC3339 앞 10자 = YYYY-MM-DD. 목록에 필요한 정밀도가 그것뿐이라 포맷터를 끌어오지 않는다.
                        상호 미등록 기본 센터는 created_at이 Go 제로값(0001-01-01)으로 오므로 "—"로 접는다. */}
                    <TD className="text-muted">{formatCreated(c.created_at)}</TD>
                  </TR>
                ))}
              </tbody>
            </Table>
          ) : (
            <EmptyState>아직 등록된 센터가 없습니다. 위 [새 센터 등록]으로 시작하세요.</EmptyState>
          )}

          {/* 상호를 채우는 곳은 이 화면이 아니다 — superadmin은 센터를 만들 뿐 운영 정보(상호·
              전화·주소)는 그 센터 대표의 몫이다(PUT /v1/center, owner 전용). 여기서 못 고치는
              값의 고치는 곳을 적어 두지 않으면 "왜 여기서 안 되지"가 다음 질문이 된다. */}
          <p className="mt-3 text-[12px] leading-relaxed text-muted">
            <b className="text-ink">상호 미등록</b> 센터의 상호·전화·주소는 그 센터 대표가 자기
            어드민의 <b className="text-ink">설정 → 센터 신원</b>에서 채웁니다. 기본 센터는 상호가
            없어도 항상 표시되고, 그 밖의 센터는 상호가 등록된 것만 표시됩니다.
          </p>
        </CardContent>
      </Card>

      <CreateCenterModal
        open={open}
        onClose={() => setOpen(false)}
        onCreated={(res, ownerEmail, mailErr) => {
          setOpen(false);
          setCreated(res);
          setCreatedOwnerEmail(ownerEmail);
          setMailError(mailErr);
        }}
      />

      {/* 생성 결과 — **한 번만 보여주고 끝나면 안 되는 정보**(대표가 로그인할 이메일)라
          별도 카드로 남긴다. 모달은 닫히면 사라진다. */}
      {created && (
        <Card>
          <CardHeader className="flex items-center justify-between gap-3">
            <CardTitle>등록 완료 — {created.center.name}</CardTitle>
            <Button variant="ghost" size="sm" onClick={() => setCreated(null)}>
              닫기
            </Button>
          </CardHeader>
          <CardContent className="space-y-3 text-[13.5px] leading-relaxed">
            <p>
              센터 <b className="text-ink">{created.center.name}</b>(
              <span className="font-mono">{created.center.id}</span>)와 대표{" "}
              <b className="text-ink">{created.owner.name}</b> 계정을 만들었습니다.
            </p>

            {/* v2.36 — 이 카드의 핵심. 종전엔 "비밀번호 재설정을 받으라고 안내하세요"라는 문장뿐이라
                superadmin이 대표에게 줄 수 있는 것이 아무것도 없었다(메일도 안 나갔다). */}
            <InitialPasswordNotice
              email={createdOwnerEmail}
              password={created.initial_password}
              who="대표"
            />

            {mailError === "" ? (
              <p className="text-[12.5px] text-ok">
                비밀번호 설정 메일도 함께 보냈어요 — 대표가 메일로 직접 정해도 됩니다.
              </p>
            ) : mailError ? (
              <p className="text-[12.5px] text-warn">
                비밀번호 설정 메일은 보내지 못했어요({mailError}). 위 비밀번호로 로그인하면 되고,
                메일이 필요하면 대표가 로그인 화면의 "비밀번호를 잊으셨나요"를 누르면 됩니다.
              </p>
            ) : null}

            <p className="text-muted">
              대표가 로그인한 뒤 <b className="text-ink">설정</b>에서 센터 신원·사업자 정보·운영
              정책을 채우고 직원과 회원을 등록하면 됩니다. 회원이 앱에서 연결되는 데 필요한 것은{" "}
              <b className="text-ink">회원 등록 시 입력한 휴대폰 번호</b>뿐입니다.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function CreateCenterModal({
  open,
  onClose,
  onCreated,
}: {
  open: boolean;
  onClose: () => void;
  onCreated: (res: CenterCreated, ownerEmail: string, mailError: string | null) => void;
}) {
  const [id, setId] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [address, setAddress] = useState("");
  const [ownerName, setOwnerName] = useState("");
  const [ownerEmail, setOwnerEmail] = useState("");
  const create = useCreateCenter();

  function reset() {
    setId("");
    setName("");
    setPhone("");
    setAddress("");
    setOwnerName("");
    setOwnerEmail("");
    create.reset();
  }

  // 서버와 **같은 규칙**으로 미리 막는다. 400을 받고 나서야 규칙을 알게 되는 폼을 만들지 않는다.
  const idOk = CENTER_ID_PATTERN.test(id.trim().toLowerCase());
  const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ownerEmail.trim());
  const canSubmit =
    idOk && name.trim() !== "" && ownerName.trim() !== "" && emailOk && !create.isPending;

  // v2.36 — 생성 뒤 **비밀번호 설정 메일까지** 보낸다. 종전엔 이 호출이 없어서(트레이너 초대
  // 화면에만 있었다) 새 센터 대표는 메일도 못 받고 비밀번호도 모르는 계정만 받았다.
  //
  // 메일 실패를 생성 실패로 되돌리지 않는다(InviteStaffModal이 세운 규약): 계정은 이미
  // 만들어졌고, 이제는 최초 비밀번호라는 대체 경로가 응답에 실려 오므로 메일이 실패해도
  // 대표는 로그인할 수 있다. 실패 사유는 화면이 그대로 말한다.
  async function submit() {
    if (!canSubmit) return;
    const email = ownerEmail.trim().toLowerCase();
    try {
      const res = await create.mutateAsync({
        id: id.trim().toLowerCase(),
        name: name.trim(),
        phone: phone.trim(),
        address: address.trim(),
        owner: { name: ownerName.trim(), email },
      });
      let mailError: string | null = "";
      try {
        await sendPasswordResetEmail(auth, email);
      } catch (e) {
        mailError = mailErrorKo(e);
      }
      reset();
      onCreated(res, email, mailError);
    } catch {
      // 생성 실패는 useCreateCenter의 error 상태가 이미 화면에 그린다(아래 ErrorState).
    }
  }

  return (
    <Modal
      open={open}
      onClose={() => {
        reset();
        onClose();
      }}
      closeDisabled={create.isPending}
      title="새 센터 등록"
    >
      <div className="space-y-4">
        <section className="space-y-3">
          <div className="text-[12px] font-bold uppercase tracking-wider text-muted">센터</div>
          <div>
            <Label htmlFor="c-name">센터 이름</Label>
            <Input
              id="c-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="라이즈 강남 2호점"
              maxLength={60}
            />
          </div>
          <div>
            <Label htmlFor="c-id">센터 ID</Label>
            <Input
              id="c-id"
              value={id}
              onChange={(e) => setId(e.target.value)}
              placeholder="gangnam-2"
              autoCapitalize="none"
              spellCheck={false}
              className="font-mono"
            />
            {/* **저장 후 바꿀 수 없다**는 사실을 입력 시점에 말한다 — 데이터 경로(centers/{id})의
                키라서, 나중에 바꾸려면 그 센터의 모든 문서를 옮겨야 한다. */}
            <p className="mt-1 text-[12px] text-muted">
              소문자 영문·숫자·하이픈 2~30자. 데이터 저장 경로가 되는 값이라{" "}
              <b className="text-ink">등록 후에는 바꿀 수 없습니다.</b>
              {id.trim() !== "" && !idOk && (
                <span className="ml-1 text-warn">형식을 확인해주세요 (예: gangnam-2)</span>
              )}
            </p>
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label htmlFor="c-phone">전화 (선택)</Label>
              <Input
                id="c-phone"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="02-555-0000"
                maxLength={20}
              />
            </div>
            <div>
              <Label htmlFor="c-addr">주소 (선택)</Label>
              <Input
                id="c-addr"
                value={address}
                onChange={(e) => setAddress(e.target.value)}
                placeholder="서울 강남구 …"
                maxLength={120}
              />
            </div>
          </div>
        </section>

        <section className="space-y-3 border-t border-line pt-4">
          <div className="text-[12px] font-bold uppercase tracking-wider text-muted">
            센터 대표 계정
          </div>
          {/* 왜 같은 폼에 있는지 한 줄로 — 안 적으면 "나중에 초대하면 되지 않나"로 읽힌다. */}
          <p className="text-[12px] leading-relaxed text-muted">
            직원 초대는 그 센터 대표만 할 수 있어서, 최초 대표는 센터를 만들 때 함께 등록합니다.
            이 이메일이 <b className="text-ink">어드민 로그인 ID</b>가 됩니다.
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label htmlFor="o-name">대표 이름</Label>
              <Input
                id="o-name"
                value={ownerName}
                onChange={(e) => setOwnerName(e.target.value)}
                placeholder="김센터장"
              />
            </div>
            <div>
              <Label htmlFor="o-email">대표 이메일</Label>
              <Input
                id="o-email"
                type="email"
                value={ownerEmail}
                onChange={(e) => setOwnerEmail(e.target.value)}
                placeholder="owner@example.com"
                autoCapitalize="none"
                spellCheck={false}
              />
              {ownerEmail.trim() !== "" && !emailOk && (
                <p className="mt-1 text-[12px] text-warn">이메일 형식을 확인해주세요.</p>
              )}
            </div>
          </div>
          <p className="text-[12px] leading-relaxed text-muted">
            이미 다른 센터에 연결된 이메일은 쓸 수 없습니다 — 그 계정이 원래 센터 접근을 잃기
            때문에 서버가 막습니다. 센터마다 다른 이메일을 쓰세요.
          </p>
        </section>

        {create.isError && <ErrorState error={create.error} />}

        <div className="flex justify-end gap-2 border-t border-line pt-4">
          <Button
            variant="ghost"
            onClick={() => {
              reset();
              onClose();
            }}
            disabled={create.isPending}
          >
            취소
          </Button>
          <Button onClick={submit} disabled={!canSubmit}>
            {create.isPending ? "등록 중…" : "센터 등록"}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
