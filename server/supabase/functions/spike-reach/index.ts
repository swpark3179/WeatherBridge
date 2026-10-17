// Phase 0 스파이크: Edge Function에서 날씨 API에 접근 가능한지, 지연은 얼마인지 측정한다.
import { checkSpikeToken, json } from "../_shared/guard.ts";
import {
  kmaVilageUrl,
  openMeteoUrl,
  probeJson,
  summarizeKma,
  summarizeOpenMeteo,
} from "./probes.ts";

Deno.serve(async (req) => {
  const denied = checkSpikeToken(req, Deno.env.get("SPIKE_TOKEN"));
  if (denied) return denied;

  const kmaKey = Deno.env.get("KMA_SERVICE_KEY");
  const [openMeteo, kma] = await Promise.all([
    probeJson(openMeteoUrl(), summarizeOpenMeteo),
    kmaKey
      ? probeJson(kmaVilageUrl(kmaKey, Date.now()), summarizeKma)
      : Promise.resolve({ skipped: "KMA_SERVICE_KEY 시크릿 미설정" }),
  ]);

  return json({
    checkedAt: new Date().toISOString(),
    region: Deno.env.get("SB_REGION") ?? null,
    openMeteo,
    kma,
  });
});
