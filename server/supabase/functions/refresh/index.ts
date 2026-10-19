// 주기 수집: 활성 장소의 예보 캐시 갱신 + 예보·관측 기록. pg_cron이 매시 20분에 `?async=1`로 호출한다.
import { refreshAll } from "../_shared/forecast_service.ts";
import { checkSpikeToken, json } from "../_shared/guard.ts";
import { liveDeps } from "../_shared/live.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

Deno.serve(async (req) => {
  const denied = checkSpikeToken(req, Deno.env.get("SPIKE_TOKEN"));
  if (denied) return denied;

  try {
    const run = refreshAll(liveDeps()).then((summary) => {
      console.log(JSON.stringify({ refresh: summary }));
      return summary;
    });
    if (new URL(req.url).searchParams.get("async") === "1" && typeof EdgeRuntime !== "undefined") {
      EdgeRuntime.waitUntil(run.catch((e) => console.error("refresh failed", e)));
      return json({ accepted: true }, 202);
    }
    return json(await run);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
