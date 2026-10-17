# Phase 0 기술 검증 (스파이크)

본 개발 전에 위험이 큰 부분을 실제로 확인합니다. 결과는 아래 표에 기록합니다.

## S1. 서버 → 날씨 API 접근성 (`spike-reach`)
Supabase Edge Function(서울 리전)에서 Open-Meteo와 data.go.kr에 접근되는지, 지연은 얼마인지 확인.

```bash
curl -s https://<project-ref>.supabase.co/functions/v1/spike-reach -H "x-spike-token: $SPIKE_TOKEN"
```
- 합격 기준: Open-Meteo 200 + 3개 모델(`ecmwf_ifs025`, `ncep_gfs_seamless`, `dwd_icon_seamless`) 강수확률 값 존재 / 기상청 `resultCode 00` + POP 항목 존재 / 각 2초 이내

| 날짜 | Open-Meteo | 기상청 | 비고 |
|---|---|---|---|
| | | | Supabase 프로젝트 생성 대기 |

## S2. 서버 → APNs 발송 (`spike-apns`) — 개발자 계정 필요
Edge Function에서 APNs(HTTP/2)로 발송되는지와 Live Activity 브로드캐스트 흐름 전체를 확인.

준비: [setup.md](setup.md) 4~6번, TestFlight로 앱 설치 → 실험실 탭에서 **push-to-start 토큰** 복사.

```bash
F=https://<project-ref>.supabase.co/functions/v1/spike-apns
H=(-H "x-spike-token: $SPIKE_TOKEN" -H "content-type: application/json")

# 1) 채널 생성 → 응답의 channelId 기록
curl -s $F "${H[@]}" -d '{"action":"create-channel"}'
# 2) 원격 시작 (앱이 꺼진 상태에서도 잠금화면에 떠야 함)
curl -s $F "${H[@]}" -d '{"action":"start-sample","deviceToken":"<push-to-start 토큰>","channelId":"<채널>","minutes":10}'
# 3) 채널로 업데이트 → 헤드라인이 "업데이트된 샘플"로 바뀌는지
curl -s $F "${H[@]}" -d '{"action":"update-sample","channelId":"<채널>"}'
# 4) 종료 → 즉시 사라지는지
curl -s $F "${H[@]}" -d '{"action":"end-sample","channelId":"<채널>"}'
```
TestFlight 빌드는 production APNs를 쓰므로 `"env":"production"`을 추가합니다.

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
