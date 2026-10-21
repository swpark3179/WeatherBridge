#!/usr/bin/env bash
# 배포된 Edge Functions 점검. 좌표·토큰은 출력하지 않는다.
#   PROJECT_ID=<ref> SPIKE_TOKEN=<token> [SUPABASE_REGION=ap-northeast-2] [SUPABASE_API_KEY=sb_publishable_…] \
#     bash server/scripts/smoke.sh
# SUPABASE_REGION을 주면 그 리전에서 함수를 실행한다(x-region). 없으면 호출한 곳에서 가까운 리전.
# SUPABASE_API_KEY(publishable)를 주면 익명 사용자를 만들어 앱 경로(set_place → register_device → today → set_trip → trips)를
# 점검하고 지운다.
# SMOKE_BASE_URL을 주면 그 주소로 호출한다(로컬 확인용).
set -uo pipefail

: "${SPIKE_TOKEN:?SPIKE_TOKEN이 필요합니다}"
BASE="${SMOKE_BASE_URL:-https://${PROJECT_ID:?SUPABASE_PROJECT_ID가 필요합니다}.supabase.co/functions/v1}"
ROOT="${BASE%/functions/v1}"
FAILED=0
REGION_HEADER=()
[ -n "${SUPABASE_REGION:-}" ] && REGION_HEADER=(-H "x-region: ${SUPABASE_REGION}")

# call METHOD PATH → BODY, STATUS
call() {
  local out
  out=$(curl -sS -X "$1" -H "x-spike-token: ${SPIKE_TOKEN}" ${REGION_HEADER[@]+"${REGION_HEADER[@]}"} \
    -w $'\n%{http_code}' "${BASE}/$2")
  BODY=$(printf '%s' "$out" | sed '$d')
  STATUS=$(printf '%s' "$out" | tail -n1)
}
# app METHOD URL [JSON] → 앱처럼 publishable key(+ 사용자 토큰)로 호출. BODY, STATUS
app() {
  local out auth=()
  [ -n "${USER_TOKEN:-}" ] && auth=(-H "authorization: Bearer ${USER_TOKEN}")
  out=$(curl -sS -X "$1" -H "apikey: ${SUPABASE_API_KEY}" ${auth[@]+"${auth[@]}"} \
    ${REGION_HEADER[@]+"${REGION_HEADER[@]}"} -H "content-type: application/json" \
    ${3:+-d "$3"} -w $'\n%{http_code}' "$2")
  BODY=$(printf '%s' "$out" | sed '$d')
  STATUS=$(printf '%s' "$out" | tail -n1)
}
fail() { echo "::error::$*"; FAILED=1; }
warn() { echo "::warning::$*"; }

# epoch 초 → KST 표기
KST_DEF='def kst: . + 32400 | strftime("%m/%d %H시");'

echo "## 1. spike-reach (외부 API 접근성)"
call GET spike-reach
if [ "$STATUS" != 200 ]; then
  fail "spike-reach HTTP $STATUS: $BODY"
else
  echo "$BODY" | jq '{region, openMeteo: {ok: .openMeteo.ok, ms: .openMeteo.ms,
    models: (.openMeteo.detail.models // {} | map_values(.nonNull))}, kma}'
  echo "$BODY" | jq -e '.openMeteo.ok' >/dev/null || fail "Open-Meteo 접근 실패"
  echo "$BODY" | jq -e '.kma.ok == true' >/dev/null || warn "기상청: $(echo "$BODY" | jq -c '.kma')"
fi

echo "## 2. refresh (수집·기록)"
call POST refresh
if [ "$STATUS" != 200 ]; then
  fail "refresh HTTP $STATUS: $BODY"
else
  echo "$BODY" | jq .
  [ "$(echo "$BODY" | jq '.places')" -gt 0 ] || warn "등록된 장소가 없습니다 (docs/setup.md 장소 등록 SQL)"
  [ "$(echo "$BODY" | jq '.errors | length')" -eq 0 ] || warn "refresh 오류: $(echo "$BODY" | jq -c '.errors')"
fi

for kind in home office; do
  echo "## 3. forecast ($kind)"
  call GET "forecast?kind=$kind"
  if [ "$STATUS" = 404 ]; then
    warn "$kind 장소가 등록되지 않았습니다"
    continue
  elif [ "$STATUS" != 200 ]; then
    fail "forecast($kind) HTTP $STATUS: $BODY"
    continue
  fi
  echo "$BODY" | jq -r "$KST_DEF"'
    "장소: \(.place.name)  최대 \(.maxPop)%  강조: \(.highlight)",
    "소스: \(.sources | map("\(.provider)(\(.hourlySlots)h)") | join(", "))",
    (.errors[]? | "오류: \(.)"),
    "비 구간: \(.windows | map("\(.start | kst)~\(.end | kst) \(.maxPop)%") | join(", ")
      | if . == "" then "없음" else . end)",
    (.hours[:24][] | "  \(.t | kst)  종합 \(.consensus // "-")%  "
      + (.families | to_entries | map("\(.key) \(.value)") | join(" / "))
      + (if .rainy then "  ☔" else "" end))
  '
  [ "$(echo "$BODY" | jq '.sources | length')" -ge 3 ] || fail "forecast($kind) 소스가 3개 미만"
done

echo "## 4. briefing"
call GET briefing
if [ "$STATUS" = 404 ]; then
  warn "집·회사가 등록되지 않았습니다"
elif [ "$STATUS" != 200 ]; then
  fail "briefing HTTP $STATUS: $BODY"
else
  echo "$BODY" | jq '{headline: .state.headline, highlight: .state.highlight, summary, firstHour,
    places: [.state.places[] | {name, temp, maxPop, rainWindow}], errors}'
fi

echo "## 5. dispatch (요약 알림, 발송 없이)"
call GET "dispatch?dry_run=1"
if [ "$STATUS" != 200 ]; then
  fail "dispatch HTTP $STATUS: $BODY"
else
  echo "$BODY" | jq '{candidates, due, errors}'
  [ "$(echo "$BODY" | jq '.errors | length')" -eq 0 ] || warn "dispatch 오류: $(echo "$BODY" | jq -c '.errors')"
fi

echo "## 6. today·trips (앱 사용자 인증)"
for fn in today trips; do
  STATUS=$(curl -sS -o /dev/null -w '%{http_code}' ${REGION_HEADER[@]+"${REGION_HEADER[@]}"} "${BASE}/${fn}")
  [ "$STATUS" = 401 ] && echo "${fn}: 토큰 없이 호출 → 401 (정상)" || fail "${fn}가 토큰 없이 HTTP $STATUS를 돌려줬습니다 (401이어야 함)"
done

if [ -z "${SUPABASE_API_KEY:-}" ]; then
  warn "SUPABASE_API_KEY가 없어 익명 사용자 점검을 건너뜁니다"
else
  USER_TOKEN=""
  app POST "${ROOT}/auth/v1/signup" '{}'
  if [ "$STATUS" != 200 ]; then
    warn "익명 가입 실패 HTTP $STATUS: $(echo "$BODY" | jq -c '{code, msg: (.msg // .message)}' 2>/dev/null) — Supabase에서 Allow anonymous sign-ins를 켰는지 확인 (docs/setup.md)"
  else
    USER_TOKEN=$(echo "$BODY" | jq -r '.access_token')
    USER_ID=$(echo "$BODY" | jq -r '.user.id')
    echo "익명 사용자 ${USER_ID:0:8}… 생성"
    # 점검이 실패해도 사용자는 지운다
    cleanup() {
      [ -n "${USER_TOKEN:-}" ] || return 0
      app POST "${ROOT}/rest/v1/rpc/delete_my_account" '{}'
      [[ "$STATUS" == 20[04] ]] && echo "익명 사용자 삭제" || fail "delete_my_account HTTP $STATUS: $BODY"
      USER_TOKEN=""
    }
    trap cleanup EXIT

    # 공개 좌표(서울시청)
    app POST "${ROOT}/rest/v1/rpc/set_place" '{"p_kind":"home","p_name":"점검","p_lat":37.5665,"p_lon":126.978}'
    [ "$STATUS" = 200 ] || fail "set_place HTTP $STATUS: $BODY"

    # 앱이 실행할 때마다 부르는 기기 등록. 가짜 토큰(sandbox)이라 발송 대상이 아니고, 계정 삭제 때 함께 지워진다.
    app POST "${ROOT}/rest/v1/rpc/register_device" \
      "{\"p_token\":\"$(openssl rand -hex 32)\",\"p_env\":\"sandbox\",\"p_app_version\":\"smoke\"}"
    if [[ "$STATUS" == 20[04] ]]; then
      app GET "${ROOT}/rest/v1/devices?select=apns_env,active,app_version"
      if [ "$STATUS" = 200 ] && [ "$(echo "$BODY" | jq '[.[] | select(.active and .apns_env == "sandbox")] | length')" = 1 ]; then
        echo "기기 등록 → 본인 기기 1대 확인"
      else
        fail "register_device 뒤 기기 조회 HTTP $STATUS: $BODY"
      fi
    else
      fail "register_device HTTP $STATUS: $BODY"
    fi

    app GET "${BASE}/today"
    if [ "$STATUS" != 200 ]; then
      fail "today HTTP $STATUS: $BODY"
    else
      echo "$BODY" | jq '{threshold, headline: .briefing.state.headline,
        places: [.places[] | {kind, name, maxPop, hours: (.hours | length),
          sources: [.sources[].provider], errors,
          tempHistory: (.tempHistory | if . then {providers, hours: (.temps | length)} else null end),
          days: [(.days // [])[] | "\(.pop)%\(if .rainy then "☔" else "" end)"]}]}'
      [ "$(echo "$BODY" | jq '.places[0].sources | length')" -ge 3 ] || fail "today 소스가 3개 미만"
      echo "$BODY" | jq -e '.places[0].tempHistory.temps | length > 0' >/dev/null || fail "today에 기온 비교용 기록(tempHistory)이 없습니다"
      echo "$BODY" | jq -e '.places[0].days | length > 0' >/dev/null || fail "today에 7일 보기용 날짜별 비 소식(days)이 없습니다"
      echo "$BODY" | jq -e 'tostring | test("37\\.5") | not' >/dev/null || fail "today 응답에 좌표가 있습니다"
    fi

    call GET "dispatch?dry_run=1&user_id=${USER_ID}"
    if [ "$STATUS" = 200 ]; then
      echo "$BODY" | jq '{preview: .previews[0].payload.aps.alert}'
    else
      fail "dispatch(dry_run, user) HTTP $STATUS: $BODY"
    fi

    echo "## 7. trips (여행: 도쿄역, 모레부터 사흘)"
    TRIP_START=$(date -u -d '+2 day' +%F)
    TRIP_END=$(date -u -d '+4 day' +%F)
    app POST "${ROOT}/rest/v1/rpc/set_trip" \
      "{\"p_name\":\"점검 여행\",\"p_lat\":35.6812,\"p_lon\":139.7671,\"p_tz\":\"Asia/Tokyo\",\"p_start\":\"${TRIP_START}\",\"p_end\":\"${TRIP_END}\"}"
    if [ "$STATUS" != 200 ]; then
      fail "set_trip HTTP $STATUS: $BODY"
    else
      TRIP_ID=$(echo "$BODY" | jq -r '.')
      app GET "${BASE}/trips"
      if [ "$STATUS" != 200 ]; then
        fail "trips HTTP $STATUS: $BODY"
      else
        # 날짜마다 기온에 쓴 모델과 운량·적설이 실제로 오는지 본다(모델마다 예보 범위가 다르다).
        echo "$BODY" | jq '{home: (.home | if . then {name, tz,
            recent: [.recent[] | "\(.providers[0]) \(.temps | length)h"]} else null end),
          trips: [.trips[] | {name, tz, startDate, endDate, watched, days: [.days[] | {date,
            destination: (.destination | if . then
              {models: (.temps.providers // []), cloud, snowCm, pop: .rain.pop} else null end),
            home: (.home | if . then {models: (.temps.providers // []), cloud, pop: .rain.pop}
              else null end)}]}]}'
        echo "$BODY" | jq -e '.trips | length == 1 and .[0].watched' >/dev/null || fail "trips: 등록한 여행이 없거나 예보를 받지 않습니다"
        echo "$BODY" | jq -e '.trips[0].days | length == 3 and all(.destination.temps.temps | length > 0)' >/dev/null ||
          fail "trips: 여행 날짜마다 목적지 기온이 있어야 합니다"
        echo "$BODY" | jq -e 'any(.trips[0].days[]; .destination.cloud != null)' >/dev/null || warn "trips: 목적지 운량이 없습니다"
        echo "$BODY" | jq -e '.home.recent | length > 0' >/dev/null || fail "trips: 집의 지난 기온(home.recent)이 없습니다"
        echo "$BODY" | jq -e 'tostring | test("139\\.7|37\\.5") | not' >/dev/null || fail "trips 응답에 좌표가 있습니다"
      fi
      app POST "${ROOT}/rest/v1/rpc/delete_trip" "{\"p_id\":\"${TRIP_ID}\"}"
      [[ "$STATUS" == 20[04] ]] && echo "여행 삭제" || fail "delete_trip HTTP $STATUS: $BODY"
    fi
    cleanup
  fi
fi

exit $FAILED
