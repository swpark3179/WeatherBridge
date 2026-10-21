// 앱 "여행" 화면: 로그인한 사용자의 여행마다 날짜별 목적지·집 날씨와 집의 지난 기온. GET
// 사용자 JWT(Authorization: Bearer)는 @supabase/server가 프로젝트 JWKS로 검증한다(today와 같음).
import { withSupabase } from "npm:@supabase/server@1.9.0";
import { json } from "../_shared/guard.ts";
import { liveDeps } from "../_shared/live.ts";
import { DEFAULT_THRESHOLD } from "../_shared/today.ts";
import { buildTrips, loadTripForecasts } from "../_shared/trips.ts";

Deno.serve(
  withSupabase({ auth: "user" }, async (_req, ctx) => {
    const userId = ctx.userClaims?.id;
    if (!userId) return json({ error: "로그인이 필요합니다" }, 401);
    try {
      const deps = liveDeps();
      const [places, trips, settings] = await Promise.all([
        deps.repo.listUserPlaces(userId),
        deps.repo.listUserTrips(userId),
        deps.repo.getUserSettings(userId),
      ]);
      const home = places.find((p) => p.kind === "home") ?? null;
      const loaded = await loadTripForecasts(deps, home, trips);
      return json(buildTrips(loaded, {
        nowSec: Math.floor(deps.nowMs() / 1000),
        threshold: settings?.threshold ?? DEFAULT_THRESHOLD,
      }));
    } catch (e) {
      console.error("trips failed", e);
      return json({ error: String(e) }, 500);
    }
  }),
);
