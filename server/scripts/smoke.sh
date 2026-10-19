#!/usr/bin/env bash
# 배포된 Edge Functions 점검. 좌표·토큰은 출력하지 않는다.
#   PROJECT_ID=<ref> SPIKE_TOKEN=<token> [SUPABASE_REGION=ap-northeast-2] bash server/scripts/smoke.sh
# SUPABASE_REGION을 주면 그 리전에서 함수를 실행한다(x-region). 없으면 호출한 곳에서 가까운 리전.
# SMOKE_BASE_URL을 주면 그 주소로 호출한다(로컬 확인용).
set -uo pipefail

: "${SPIKE_TOKEN:?SPIKE_TOKEN이 필요합니다}"
BASE="${SMOKE_BASE_URL:-https://${PROJECT_ID:?SUPABASE_PROJECT_ID가 필요합니다}.supabase.co/functions/v1}"
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

exit $FAILED
