// 앱 "오늘"·"비교" 화면: 로그인한 사용자의 집·회사 48시간 종합 + 오늘 브리핑. GET
// 사용자 JWT(Authorization: Bearer)는 @supabase/server가 프로젝트 JWKS로 검증한다.
// 플랫폼의 기본 검사(verify_jwt)는 비대칭 서명 키 토큰을 거부하는 경우가 있어 끈다(config.toml).
import { withSupabase } from "npm:@supabase/server@1.9.0";
import { json } from "../_shared/guard.ts";
import { liveDeps } from "../_shared/live.ts";
import { buildToday, DEFAULT_THRESHOLD, loadForecasts } from "../_shared/today.ts";

Deno.serve(
  withSupabase({ auth: "user" }, async (_req, ctx) => {
    const userId = ctx.userClaims?.id;
    if (!userId) return json({ error: "로그인이 필요합니다" }, 401);
    try {
      const deps = liveDeps();
      const [places, settings] = await Promise.all([
        deps.repo.listUserPlaces(userId),
        deps.repo.getUserSettings(userId),
      ]);
      if (places.length === 0) {
        return json({ error: "집·회사를 먼저 등록해 주세요", code: "no_places" }, 404);
      }
      const loaded = await loadForecasts(deps, places);
      return json(buildToday(loaded, {
        nowSec: Math.floor(deps.nowMs() / 1000),
        tz: settings?.tz ?? places[0].tz,
        threshold: settings?.threshold ?? DEFAULT_THRESHOLD,
      }));
    } catch (e) {
      console.error("today failed", e);
      return json({ error: String(e) }, 500);
    }
  }),
);
