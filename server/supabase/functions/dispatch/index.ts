// 요약 알림 발송. pg_cron이 매분 `?async=1`로 호출한다.
// 점검: `?dry_run=1` (기록·발송 없이 대상 수 확인), `&user_id=` (그 사용자의 알림 문구 미리 보기)
import { runDispatch } from "../_shared/dispatch.ts";
import { checkSpikeToken, json } from "../_shared/guard.ts";
import { apnsConfigFromEnv, liveDeps } from "../_shared/live.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

Deno.serve(async (req) => {
  const denied = checkSpikeToken(req, Deno.env.get("SPIKE_TOKEN"));
  if (denied) return denied;

  try {
    const url = new URL(req.url);
    const run = runDispatch(liveDeps(), {
      apns: apnsConfigFromEnv(),
      dryRun: url.searchParams.get("dry_run") === "1",
      userId: url.searchParams.get("user_id") ?? undefined,
    }).then((report) => {
      // 매분 실행되므로 할 일이 있었을 때만 남긴다
      if (report.due > 0 || report.errors.length > 0) {
        console.log(JSON.stringify({ dispatch: report }));
      }
      return report;
    });
    if (url.searchParams.get("async") === "1" && typeof EdgeRuntime !== "undefined") {
      EdgeRuntime.waitUntil(run.catch((e) => console.error("dispatch failed", e)));
      return json({ accepted: true }, 202);
    }
    return json(await run);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
