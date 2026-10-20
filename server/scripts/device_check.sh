#!/usr/bin/env bash
# TestFlight로 설치한 기기 점검. 운영 토큰 함수만 부르고 토큰·좌표는 출력하지 않는다.
#   PROJECT_ID=<ref> SPIKE_TOKEN=<token> [SUPABASE_REGION=ap-northeast-2] bash server/scripts/device_check.sh <check>
# check
#   status         기기 등록, 요약 알림 설정, 최근 발송 기록(예정 시각 대비 지연)
#   test-alert     가장 최근에 앱을 연 기기로 테스트 알림
#   live-activity  push-to-start로 샘플 브리핑 시작 → 업데이트 → 종료 (docs/spikes.md S2)
#                  LA_MINUTES(기본 10): 시작·업데이트 뒤 이 시간이 지나면 "출근 시간 지남"(stale)
#                  LA_END(기본 1): 0이면 종료를 보내지 않는다(stale 확인용)
#                  LA_STEP_SEC(기본 60): 단계 사이 대기
# SMOKE_BASE_URL을 주면 그 주소로 호출한다(로컬 확인용).
set -uo pipefail

CHECK="${1:-status}"
: "${SPIKE_TOKEN:?SPIKE_TOKEN이 필요합니다}"
BASE="${SMOKE_BASE_URL:-https://${PROJECT_ID:?SUPABASE_PROJECT_ID가 필요합니다}.supabase.co/functions/v1}"
FAILED=0
REGION_HEADER=()
[ -n "${SUPABASE_REGION:-}" ] && REGION_HEADER=(-H "x-region: ${SUPABASE_REGION}")

# call METHOD PATH [JSON] → BODY, STATUS
call() {
  local out
  out=$(curl -sS -X "$1" -H "x-spike-token: ${SPIKE_TOKEN}" ${REGION_HEADER[@]+"${REGION_HEADER[@]}"} \
    -H "content-type: application/json" ${3:+-d "$3"} -w $'\n%{http_code}' "${BASE}/$2")
  BODY=$(printf '%s' "$out" | sed '$d')
  STATUS=$(printf '%s' "$out" | tail -n1)
}
fail() { echo "::error::$*"; FAILED=1; }
warn() { echo "::warning::$*"; }

# epoch 초 → KST 표기
KST_DEF='def kst: . + 32400 | strftime("%m/%d %H:%M:%S");'

# spike-apns 호출. 함수 응답이 200이고 APNs 상태가 2xx면 0
apns() {
  local label="$1" body="$2"
  call POST spike-apns "$body"
  if [ "$STATUS" != 200 ]; then
    fail "$label: HTTP $STATUS $(echo "$BODY" | jq -c '.error // .' 2>/dev/null)"
    return 1
  fi
  local s
  s=$(echo "$BODY" | jq -r '.status')
  echo "$label: APNs $s$(echo "$BODY" | jq -r '
    (if .device then "  기기 \(.device)" else "" end)
    + (if (.body | type) == "object" and .body.reason then "  \(.body.reason)" else "" end)')"
  if [[ "$s" != 2?? ]]; then
    fail "$label: APNs $s"
    return 1
  fi
}

case "$CHECK" in
status)
  call GET ops-status
  if [ "$STATUS" != 200 ]; then
    fail "ops-status HTTP $STATUS: $BODY"
  else
    echo "$BODY" | jq -r "$KST_DEF"'
      "기준 \(.now | kst) KST",
      "## 기기 (최근 등록 순)",
      (if .devices == [] then "  없음" else .devices[] |
        "  \(.device)  사용자 \(.user)  \(.env)  앱 \(.appVersion // "-")"
        + "  push-to-start \(if .pushToStart then "있음" else "없음" end)"
        + "  \(if .active then "활성" else "비활성(\(.deactivatedReason // "-"))" end)"
        + "  마지막 등록 \(.lastSeenAt | kst)" end),
      "## 사용자",
      (if .users == [] then "  없음" else .users[] |
        "  \(.user)  장소 \(.places | join(",") | if . == "" then "없음" else . end)"
        + "  요약 알림 \(if .summary then "\(.summary.time) (\(.summary.tz), 강조 \(.summary.threshold)%)" else "꺼짐" end)"
      end),
      "## 최근 요약 알림",
      (if .dispatches == [] then "  없음" else .dispatches[] |
        "  \(.localDate)  사용자 \(.user)  예정 \(.scheduledAt | kst)  \(.status)  시도 \(.attempts)"
        + (if .delaySec != null then "  APNs 접수 \(.finishedAt | kst) (예정 +\(.delaySec)초)" else "" end)
        + "  \(.detail | tojson)"
      end)'
    # Phase 2 완료 기준: 가장 최근 발송이 예정 시각 1분 안
    last=$(echo "$BODY" | jq -c '[.dispatches[] | select(.status == "sent")][0] // empty')
    if [ -n "$last" ]; then
      delay=$(echo "$last" | jq '.delaySec')
      if [ "$delay" -ge 0 ] && [ "$delay" -le 60 ]; then
        echo "✅ 최근 발송은 예정 시각 +${delay}초에 APNs가 받았습니다 (기준 ±1분)"
      else
        warn "최근 발송이 예정 시각 +${delay}초에 나갔습니다 (기준 ±1분)"
      fi
    fi
    [ "$(echo "$BODY" | jq '[.devices[] | select(.active and .env == "production")] | length')" -gt 0 ] ||
      warn "production 기기가 없습니다. TestFlight 앱을 열어 온보딩을 마쳤는지, 알림을 허용했는지 확인하세요"
  fi
  ;;

test-alert)
  apns "테스트 알림" '{"action":"send-alert","env":"production"}'
  ;;

live-activity)
  minutes="${LA_MINUTES:-10}"
  step="${LA_STEP_SEC:-60}"
  [[ "$minutes" =~ ^[0-9]+$ ]] && [ "$minutes" -ge 1 ] && [ "$minutes" -le 60 ] ||
    { fail "LA_MINUTES는 1~60 사이 숫자여야 합니다"; exit 1; }
  [[ "$step" =~ ^[0-9]+$ ]] || { fail "LA_STEP_SEC는 숫자여야 합니다"; exit 1; }

  call POST spike-apns '{"action":"create-channel","env":"production"}'
  channel=$(echo "$BODY" | jq -r '.channelId // empty' 2>/dev/null)
  if [ "$STATUS" != 200 ] || [ -z "$channel" ]; then
    fail "채널 생성 실패: HTTP $STATUS $(echo "$BODY" | jq -c '{status, body, error}' 2>/dev/null)"
    exit 1
  fi
  [ "${GITHUB_ACTIONS:-}" = true ] && echo "::add-mask::$channel"
  echo "1) 채널 생성: APNs $(echo "$BODY" | jq -r '.status')"

  start=$(jq -nc --arg c "$channel" --argjson m "$minutes" \
    '{action: "start-sample", env: "production", channelId: $c, minutes: $m}')
  apns "2) 원격 시작 (${minutes}분)" "$start" || exit 1
  echo "   잠금화면에 '출근 날씨 브리핑'이 떴는지 확인하세요. ${step}초 뒤 업데이트합니다."
  sleep "$step"

  update=$(jq -nc --arg c "$channel" --argjson m "$minutes" \
    '{action: "update-sample", env: "production", channelId: $c, minutes: $m}')
  apns "3) 업데이트" "$update" || exit 1
  echo "   헤드라인이 '업데이트된 샘플'로 바뀌었는지 확인하세요."

  if [ "${LA_END:-1}" = 1 ]; then
    echo "   ${step}초 뒤 종료합니다."
    sleep "$step"
    apns "4) 종료" "$(jq -nc --arg c "$channel" '{action: "end-sample", env: "production", channelId: $c}')"
    echo "   잠금화면에서 바로 사라졌는지 확인하세요."
  else
    echo "   종료는 보내지 않습니다. 업데이트 ${minutes}분 뒤 '출근 시간 지남'으로 바뀌는지 확인하세요."
  fi
  ;;

*)
  fail "check는 status | test-alert | live-activity"
  ;;
esac

exit $FAILED
