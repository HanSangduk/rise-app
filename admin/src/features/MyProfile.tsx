// 내 프로필 · 휴무 — 트레이너 전용 탭(P58 B3).
//
// **왜 설정 탭을 여는 대신 탭을 하나 더 두나.** 서버가 트레이너 본인에게 허용하는 쓰기는 딱 둘이다
// — PUT /v1/staff/{uid}/profile · POST /v1/staff/{uid}/offdays(service.go UpdateStaffProfile·
// SetOffdays: `!p.IsOwner() && p.UID != uid`면 403, 즉 본인은 통과). 설정 탭의 나머지(운영 정책·
// 사업자 정보·센터 신원·가입 승인·체크인 QR·초대·정정·이관·퇴사)는 전부 owner 전용이라 그 탭을
// 트레이너에게 열면 카드 일곱 개가 "눌러보고 403"이 된다 — 이 어드민의 관례("403을 받는 UI를
// 만들지 않는다")와 정면으로 어긋난다. 그래서 허용된 두 동사만 이 화면이 빌려 온다
// (Settings.tsx의 OffdaysModal·ProfileModal export — 폼·검증·문구를 복제하지 않는다).
//
// 사진 업로드(POST /v1/staff/{uid}/photo)는 **owner 전용**이다(service_staff_photo.go — 센터 공용
// 버킷에 쓰는 일이라 되돌리는 수단·비용이 대표에게 있다). ProfileModal에 photoEditable=false로
// 넘겨 [사진 선택]을 그리지 않고, 그 창이 이유를 문장으로 말한다.
//
// 종전엔 이 두 동사의 유일한 호출부가 owner 게이트 뒤의 Settings.tsx라, 트레이너는 **회원 앱에
// 노출되는 자기 정보**(담당 코치 카드 — P30)를 고칠 수 없었다. 서버는 허용하는데 클라이언트가
// 막는 자리(P56 클래스 6).
import { useState } from "react";
import { CalendarOff, IdCard, Lock } from "lucide-react";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Chip,
  EmptyState,
  ErrorState,
  Spinner,
} from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { isStaffActive, todayStr } from "@/lib/format";
import { useStaff } from "@/lib/queries";
import { OffdaysModal, ProfileModal, StaffAvatar, isProfileEmpty } from "@/features/Settings";

export function MyProfile() {
  const { me } = useAuth();
  const staffQ = useStaff();
  const [editing, setEditing] = useState<"profile" | "offdays" | null>(null);

  // GET /v1/staff는 트레이너에게도 전원을 준다(남의 payout만 마스킹) — 본인 행은 항상 포함된다.
  const mine = staffQ.data?.find((s) => s.uid === me?.uid);
  const today = todayStr();
  // 지난 휴무는 이미 아무것도 막지 않는다(OffdaysModal 주석) — 앞으로의 것만 세어 보여준다.
  const upcoming = mine ? [...mine.offdays].filter((d) => d >= today).sort() : [];
  const pastCount = mine ? mine.offdays.length - upcoming.length : 0;

  return (
    <div>
      <h2 className="text-[16.5px] font-bold">내 프로필 · 휴무</h2>
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        여기서 고친 프로필은 회원 앱의 <b className="text-ink">"담당 코치" 카드</b>에 그대로
        보입니다. 휴무일로 지정한 날은 서버가 내 새 예약을 막습니다.
      </p>

      {staffQ.isLoading ? (
        <Spinner />
      ) : staffQ.isError ? (
        <ErrorState error={staffQ.error} onRetry={() => void staffQ.refetch()} />
      ) : !mine ? (
        // 로그인은 됐는데 직원 목록에 내가 없다 — 서버 UserIndex와 Staff 문서가 어긋난 상태다.
        // 화면이 고칠 수 없는 일이라 다음 행동(대표에게 확인 요청)만 남긴다.
        <EmptyState>
          내 직원 정보를 찾지 못했어요 — 대표에게 직원 등록 상태를 확인해달라고 요청해주세요.
        </EmptyState>
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>
                <IdCard className="mr-1.5 -mt-0.5 inline h-4 w-4" />
                프로필
              </CardTitle>
              {isProfileEmpty(mine.profile) ? (
                <Badge tone="warn">미등록</Badge>
              ) : (
                <Badge tone="ok">등록됨</Badge>
              )}
            </CardHeader>
            <CardContent>
              <div className="flex items-start gap-3">
                <StaffAvatar
                  name={mine.name}
                  color={mine.color}
                  photoUrl={mine.profile.photo_url}
                  size="lg"
                />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-1.5 text-[13.5px] font-bold">
                    {mine.name}
                    <Badge tone={mine.role === "owner" ? "brand" : "warn"}>
                      {mine.role === "owner" ? "대표" : "트레이너"}
                    </Badge>
                    {!isStaffActive(mine) && <Badge tone="danger">퇴사</Badge>}
                  </div>
                  <div className="mt-0.5 text-[11.5px] text-muted">
                    {mine.profile.title || "직함 미입력"}
                    {mine.profile.career_years > 0 && ` · 경력 ${mine.profile.career_years}년`}
                  </div>
                  {mine.profile.specialties.length > 0 && (
                    <div className="mt-1.5 -ml-0.5 flex flex-wrap">
                      {mine.profile.specialties.map((s) => (
                        <Chip key={s} className="cursor-default">
                          {s}
                        </Chip>
                      ))}
                    </div>
                  )}
                  {mine.profile.bio && (
                    <p className="mt-1.5 line-clamp-3 text-[11.5px] leading-[1.7] text-muted">
                      {mine.profile.bio}
                    </p>
                  )}
                  {isProfileEmpty(mine.profile) && (
                    <p className="mt-1.5 text-[11px] leading-[1.7] text-warn">
                      아직 프로필이 비어 있어요 — 회원 앱의 담당 코치 카드에 이름만 보입니다. 직함·
                      전문분야·소개를 채우면 바로 반영돼요.
                    </p>
                  )}
                </div>
              </div>
              <Button size="sm" className="mt-3" onClick={() => setEditing("profile")}>
                <IdCard className="h-3.5 w-3.5" /> 프로필 편집
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>
                <CalendarOff className="mr-1.5 -mt-0.5 inline h-4 w-4" />
                휴무일
              </CardTitle>
              <Badge tone="muted">앞으로 {upcoming.length}일</Badge>
            </CardHeader>
            <CardContent>
              {upcoming.length ? (
                <div className="-ml-0.5 flex flex-wrap">
                  {upcoming.map((d) => (
                    <Chip key={d} active className="cursor-default">
                      {d}
                    </Chip>
                  ))}
                </div>
              ) : (
                <p className="text-[11.5px] text-muted">앞으로 예정된 휴무일이 없어요.</p>
              )}
              {pastCount > 0 && (
                <p className="mt-1.5 text-[10.5px] text-muted">
                  지난 휴무 {pastCount}일은 표시하지 않아요 — 지난 날짜는 이미 아무 예약도 막지 않습니다.
                </p>
              )}
              <Button size="sm" className="mt-3" onClick={() => setEditing("offdays")}>
                <CalendarOff className="h-3.5 w-3.5" /> 휴무 설정
              </Button>
              <p className="mt-2.5 text-[10.5px] leading-[1.8] text-muted">
                휴무일엔 내 새 예약(단건·고정 스케줄 선행 생성)이 서버에서 차단돼요. 이미 잡힌 예약은
                예약 화면에서 개별 조정하세요.
              </p>
            </CardContent>
          </Card>

          {/* 이 화면이 **못 하는 것**을 감추지 않는다 — 서버가 owner에게만 허용하는 값들이다
              (UpdateStaff·UploadStaffPhoto). 버튼을 만들어 403을 받게 하는 대신 누구에게 말하면
              되는지를 적는다. */}
          <Card className="md:col-span-2">
            <CardContent className="flex items-start gap-2 pt-3.5 text-[11.5px] leading-[1.8] text-muted">
              <Lock className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              <span>
                <b className="text-ink">이름 · 프로필 사진 · 색상 · 정산 조건 · 역할은 대표만 바꿀 수
                있어요.</b>{" "}
                바꿔야 하면 대표에게 요청해주세요 — 사진은 파일을 보내주면 대표가 올려줍니다.
              </span>
            </CardContent>
          </Card>
        </div>
      )}

      {editing === "profile" && mine && (
        <ProfileModal staff={mine} photoEditable={false} onClose={() => setEditing(null)} />
      )}
      {editing === "offdays" && mine && <OffdaysModal staff={mine} onClose={() => setEditing(null)} />}
    </div>
  );
}
