# Phase 0 기술 검증 (스파이크)

본 개발 전에 위험이 큰 부분을 실제로 확인합니다. 결과는 아래 표에 기록합니다.

> Phase 1부터는 GitHub Actions의 **Server smoke** 워크플로가 S1 측정과 예보 함수 점검을 함께 실행합니다(매일 07:17 KST, 수동 실행 가능). 함수는 `x-region` 헤더로 서울 리전에서 실행합니다. 아래 명령은 PC에서 직접 확인할 때 씁니다.

## S1. 서버 → 날씨 API 접근성 (`spike-reach`)
Supabase Edge Function(서울 리전)에서 Open-Meteo와 data.go.kr에 접근되는지, 지연은 얼마인지 확인.

```bash
curl -s https://<project-ref>.supabase.co/functions/v1/spike-reach -H "x-spike-token: $SPIKE_TOKEN"
```
Windows PowerShell에서는 `curl`이 `Invoke-WebRequest`의 별칭이라 위 형식이 동작하지 않습니다. 둘 중 하나를 쓰세요.
```powershell
# 1) Windows 내장 curl.exe (한글이 깨지면 먼저 chcp 65001)
curl.exe -s "https://<project-ref>.supabase.co/functions/v1/spike-reach" -H "x-spike-token: <SPIKE_TOKEN>"

# 2) PowerShell 명령 (-Depth를 빼면 안쪽 값이 생략됨)
$r = Invoke-RestMethod -Uri "https://<project-ref>.supabase.co/functions/v1/spike-reach" -Headers @{ "x-spike-token" = "<SPIKE_TOKEN>" }
$r | ConvertTo-Json -Depth 10
```
- 합격 기준: Open-Meteo 200 + 3개 모델(`ecmwf_ifs025`, `ncep_gfs_seamless`, `dwd_icon_seamless`) 강수확률 값 존재 / 기상청 `resultCode 00` + POP 항목 존재 / 각 2초 이내

| 날짜 | Open-Meteo | 기상청 | 비고 |
|---|---|---|---|
| 2026-10-18 | ✅ 200, 1,426ms, 3개 모델 모두 48시간 값 | ⏸ 키 미등록으로 건너뜀 | 리전 `ap-northeast-2`. 같은 시각(10/18 00–05시) 모델별 값이 크게 달라 다중 소스 비교의 필요성 확인: ECMWF 4→49%, GFS 0→11%, ICON 0→8% |
| 2026-10-20 | ✅ 200, 1,288ms, 3개 모델 모두 48시간 값 | ✅ 200, 1,241ms, `resultCode 00`, 항목 980개·POP 81개(10/19 23시 발표) | `Server smoke`에서 서울 리전으로 고정해 측정. 리전을 지정하지 않으면 GitHub 러너(미국) 근처인 `us-west-2`에서 실행되고 기상청 2,535ms·Open-Meteo 914ms |

## Phase 1 실서버 점검 (`Server smoke`)
- 합격 기준
  - `refresh`: 집·회사 2곳 × 4개 소스 수집·기록, 오류 없음
  - `forecast`: 집·회사 모두 4개 계열(kma·ecmwf·ncep·dwd) 48시간
  - `briefing`: 헤드라인·장소별 요약 생성
  - cron(매시 20분)이 `refresh`를 호출해 새 발표를 수집

| 날짜(KST) | refresh | forecast | briefing | cron | 비고 |
|---|---|---|---|---|---|
| 2026-10-20 02:03 | ✅ 장소 2, 수집·기록 8건, 실황 2건, 오류 0 | ✅ 집·회사 모두 4개 소스 48시간, 비 구간 10/20 02시부터 최대 87%·86% | ✅ "☔ 집 2–24시 최대 87% · 회사 2–24시 최대 86%" | (첫 등록 직후) | 기상청 60% 안팎, 외국 모델 80~100%로 계열 간 차이가 큼(10/20 새벽) |
| 2026-10-20 06:19 | ✅ Open-Meteo 3개만 재수집, 기상청은 재수집 없음, 기록 0건(중복 제외), 실황 2건 | ✅ 집·회사 모두 4개 소스 48시간, 비 구간 10/20 06시~10/21 06시 | ✅ "☔ 집 6–24시 최대 87% · 회사 6–24시 최대 86%" | ✅ 05:20 cron이 05시 발표를 이미 수집·기록 | 그 사이 수동 호출이 없었는데도 기상청 캐시가 최신 발표(05시)여서 cron 동작으로 판단. 기상청 1,196ms·Open-Meteo 1,443ms |

## Phase 2 서버 점검 (`Server smoke` 5·6단계)
- 합격 기준
  - `dispatch` dry-run 200
  - 토큰 없는 `today` 401
  - 익명 가입 → `set_place` → `today`(4개 소스 48시간, 좌표 없음) → 알림 문구 미리 보기 → `delete_my_account`

| 날짜(KST) | dispatch | today 인증 | 익명 흐름 | 비고 |
|---|---|---|---|---|
| 2026-10-20 17:00 | ✅ 대상 0, 오류 0 | ✅ 토큰 없이 401 | ✅ 가입 → 서울시청 등록 → 4개 소스 48시간 → "오늘은 비 소식이 없어요 / 점검 비 소식 없음(최대 16%)" → 삭제 | PR #7 배포 직후. 익명 로그인·비대칭 JWT 검증이 실서버에서 동작함을 확인. 같은 시각 운영 장소(집·회사)는 17–24시 최대 80%로, 기상청 값도 서울시청 격자 20%·집 격자 60%라 위치 차이로 판단 |

## Phase 2 실기기 확인 (`Device check`)
TestFlight로 설치한 앱으로 Phase 2 완료 기준(지정 시각 ±1분 안에 요약 알림 수신)을 확인합니다.
Actions → **Device check** → Run workflow에서 점검 종류를 고릅니다. 결과에 토큰·좌표는 나오지 않고, ID는 앞 8자리만 나옵니다.

1. TestFlight에서 앱을 설치하고 온보딩을 마칩니다(집 → 회사 → 알림 허용·요약 시각).
2. `status`로 다음을 확인합니다.
   - 기기가 `production`·활성으로 등록됐는지, push-to-start 토큰이 있는지
   - 집·회사와 요약 알림 설정이 저장됐는지
3. `test-alert`로 "APNs 테스트 알림"이 오는지 봅니다. 이 알림이 오지 않으면 요약 알림도 오지 않으므로 먼저 원인을 찾습니다.
4. 앱 설정에서 요약 시각을 **지금부터 3분 뒤**로 바꾸고 휴대폰을 잠급니다. 알림이 도착한 시각을 적어 둡니다.
5. `status`의 "최근 요약 알림"에서 그날 기록이 `sent`이고, APNs 접수가 예정 시각 +60초 안인지 확인합니다.

- 합격 기준
  - 예정 시각 ±1분 안에 알림 도착
  - 발송 기록 `sent`, 같은 날 두 번 오지 않음
- 요약 알림은 현지 날짜마다 한 번만 보냅니다. 같은 날 시각을 다시 바꿔도 또 오지 않으니, 다시 확인하려면 다음 날 합니다.
- 서버는 매분 발송 대상을 고릅니다. 예정 시각 직후 실행에서 보내고, 실패하면 15분 안에서 다시 시도합니다. APNs는 휴대폰이 꺼져 있으면 1시간까지 보관했다가 전달합니다.

| 날짜(KST) | 빌드 | 기기 등록 | 테스트 알림 | 요약 알림(예정 → 도착) | 서버 기록 | 비고 |
|---|---|---|---|---|---|---|
| | | | | | | |

## S2. 서버 → APNs 발송 (`spike-apns`) — 개발자 계정 필요
Edge Function에서 APNs(HTTP/2)로 발송되는지와 Live Activity 브로드캐스트 흐름 전체를 확인.

준비: [setup.md](setup.md) "TestFlight 배포" → TestFlight로 앱 설치 → 앱을 한 번 열어 기기 등록(`Device check` `status`에서 push-to-start 토큰 "있음" 확인).

**간편 실행**: 앱을 완전히 종료(앱 전환기에서 위로 밀기)하고 휴대폰을 잠근 뒤, Actions → **Device check** → `live-activity`를 실행합니다.
- 채널 생성 → 원격 시작 → 1분 뒤 업데이트 → 1분 뒤 종료를 차례로 보냅니다.
- 기기 토큰은 서버가 DB에서 가장 최근에 등록된 기기의 것을 꺼내 쓰므로 복사할 필요가 없습니다.
- stale 확인은 `end`를 끄고 `minutes`를 2로 실행합니다. 업데이트 2분 뒤 "출근 시간 지남"으로 바뀌어야 합니다.

직접 호출할 때도 `deviceToken`을 빼면 같은 방식으로 등록된 기기를 씁니다. TestFlight 앱은 production APNs를 쓰므로 모든 요청에 `"env":"production"`을 넣습니다.

```bash
F=https://<project-ref>.supabase.co/functions/v1/spike-apns
H=(-H "x-spike-token: $SPIKE_TOKEN" -H "content-type: application/json")

# 1) 채널 생성 → 응답의 channelId 기록
curl -s $F "${H[@]}" -d '{"action":"create-channel","env":"production"}'
# 2) 원격 시작 (앱이 꺼진 상태에서도 잠금화면에 떠야 함). deviceToken을 빼면 등록된 최근 기기
curl -s $F "${H[@]}" -d '{"action":"start-sample","env":"production","channelId":"<채널>","minutes":10}'
# 3) 채널로 업데이트 → 헤드라인이 "업데이트된 샘플"로 바뀌는지
curl -s $F "${H[@]}" -d '{"action":"update-sample","env":"production","channelId":"<채널>"}'
# 4) 종료 → 즉시 사라지는지
curl -s $F "${H[@]}" -d '{"action":"end-sample","env":"production","channelId":"<채널>"}'
```

PowerShell에서는 본문을 해시테이블로 만들어 보냅니다.
```powershell
$F = "https://<project-ref>.supabase.co/functions/v1/spike-apns"
$H = @{ "x-spike-token" = "<SPIKE_TOKEN>" }
function Spike($body) {
  Invoke-RestMethod -Method Post -Uri $F -Headers $H -ContentType "application/json" `
    -Body ($body | ConvertTo-Json) | ConvertTo-Json -Depth 10
}
Spike @{ action = "create-channel"; env = "production" }
Spike @{ action = "start-sample"; env = "production"; channelId = "<채널>"; minutes = 10 }
Spike @{ action = "update-sample"; env = "production"; channelId = "<채널>" }
Spike @{ action = "end-sample"; env = "production"; channelId = "<채널>" }
```

- 합격 기준
  - 1~4 모두 APNs 2xx
  - 앱을 종료한 상태에서 2) 후 잠금화면 표시
  - 3)에서 내용 변경
  - 4)에서 사라짐
  - 4)를 보내지 않으면 `minutes` 뒤 "출근 시간 지남"(stale)으로 표시

| 날짜 | 1 채널 | 2 시작 | 3 업데이트 | 4 종료 | stale 표시 | 비고 |
|---|---|---|---|---|---|---|
| | | | | | | 개발자 계정 대기 |

## S3. 잠금화면 표시 (로컬) — 개발자 계정 필요
실험실 탭 → "샘플 브리핑 시작 (3분)" → 잠금화면/Dynamic Island 확인.

- 합격 기준
  - 집·회사 시간별 막대 표시
  - 강조 헤드라인 표시
  - 카운트다운 표시
  - 3분 뒤 stale 표시
  - 앱 재실행 시 지난 활동이 자동 종료

| 날짜 | 기기/iOS | 결과 | 비고 |
|---|---|---|---|
| | | | |
