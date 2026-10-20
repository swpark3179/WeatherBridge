// 실기기 점검: 기기 등록, 요약 알림 설정, 최근 발송 기록(예정 시각 대비 지연).
// 운영 토큰으로 호출한다. 좌표·토큰은 응답에 싣지 않는다. 워크플로: .github/workflows/device-check.yml
import { supabaseRepo } from "../_shared/db.ts";
import { checkSpikeToken, json } from "../_shared/guard.ts";
import { buildStatus } from "../_shared/status.ts";

Deno.serve(async (req) => {
  const denied = checkSpikeToken(req, Deno.env.get("SPIKE_TOKEN"));
  if (denied) return denied;

  try {
    return json(await buildStatus(supabaseRepo(), Math.floor(Date.now() / 1000)));
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
