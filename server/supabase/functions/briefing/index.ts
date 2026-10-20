// 운영자 점검용 집·회사 오늘 브리핑 (요약 알림·잠금화면 공통 형식). GET
import { aggregate } from "../_shared/aggregate.ts";
import { buildBriefing, restOfLocalDay } from "../_shared/briefing.ts";
import { ensureForecasts } from "../_shared/forecast_service.ts";
import { checkSpikeToken, json } from "../_shared/guard.ts";
import { liveDeps, operatorPlaces, publicPlace } from "../_shared/live.ts";

Deno.serve(async (req) => {
  const denied = checkSpikeToken(req, Deno.env.get("SPIKE_TOKEN"));
  if (denied) return denied;

  try {
    const deps = liveDeps();
    const places = await operatorPlaces(deps);
    const targets = (["home", "office"] as const)
      .map((kind) => places.find((p) => p.kind === kind))
      .filter((p) => p !== undefined);
    if (targets.length === 0) {
      return json(
        { error: "집·회사가 등록되지 않았습니다 (docs/setup.md의 장소 등록 SQL 참고)" },
        404,
      );
    }

    const nowSec = Math.floor(deps.nowMs() / 1000);
    const tz = targets[0].tz;
    const range = restOfLocalDay(nowSec, tz);
    const errors: string[] = [];
    const briefingPlaces = [];
    for (const place of targets) {
      const ensured = await ensureForecasts(place, deps);
      errors.push(...ensured.errors.map((e) => `${place.kind}: ${e}`));
      briefingPlaces.push({ name: place.name, aggregate: aggregate(ensured.forecasts, range) });
    }

    return json({
      places: targets.map(publicPlace),
      errors,
      ...buildBriefing({ nowSec, tz, places: briefingPlaces }),
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
