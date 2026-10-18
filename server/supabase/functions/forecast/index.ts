// 장소별 시간대별 강수확률 종합 (향후 48시간). GET ?kind=home|office 또는 ?place_id=
import { aggregate } from "../_shared/aggregate.ts";
import { ensureForecasts } from "../_shared/forecast_service.ts";
import { checkSpikeToken, json } from "../_shared/guard.ts";
import { findPlace, liveDeps, publicPlace } from "../_shared/live.ts";

const HORIZON_SEC = 48 * 3600;

Deno.serve(async (req) => {
  const denied = checkSpikeToken(req, Deno.env.get("SPIKE_TOKEN"));
  if (denied) return denied;

  try {
    const deps = liveDeps();
    const place = await findPlace(deps, new URL(req.url));
    if (!place) {
      return json({ error: "등록된 장소가 없습니다 (docs/setup.md의 장소 등록 SQL 참고)" }, 404);
    }

    const { forecasts, errors } = await ensureForecasts(place, deps);
    const from = Math.floor(deps.nowMs() / 3_600_000) * 3600;
    const result = aggregate(forecasts, { from, to: from + HORIZON_SEC });

    return json({
      place: publicPlace(place),
      generatedAt: new Date(deps.nowMs()).toISOString(),
      sources: forecasts.map((f) => ({
        provider: f.provider,
        family: f.family,
        issuedAt: f.issuedAt,
        fetchedAt: f.fetchedAt,
        hourlySlots: f.slots.filter((s) =>
          s.span === 1 && s.t >= from && s.t < from + HORIZON_SEC
        ).length,
      })),
      errors,
      ...result,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
