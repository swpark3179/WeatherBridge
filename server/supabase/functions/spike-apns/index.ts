// Phase 0 스파이크: Edge Function → APNs(HTTP/2) 발송과 Live Activity 브로드캐스트 흐름 검증.
//
// POST JSON { action, env?, deviceToken?, channelId?, minutes?, payload? }
//   create-channel : 브로드캐스트 채널 생성(최근 1건 저장) → 응답 channelId
//   start-sample   : push-to-start 토큰(deviceToken)으로 샘플 브리핑 시작, channelId 있으면 채널 구독
//   update-sample  : 채널로 샘플 업데이트 (priority 5)
//   end-sample     : 채널로 종료 (즉시 사라짐)
//   send-alert     : 기기 토큰(deviceToken)으로 일반 알림
import {
  type ApnsEnv,
  broadcast,
  buildLiveActivityEnd,
  buildLiveActivityStart,
  buildLiveActivityUpdate,
  createChannel,
  liveActivityTopic,
  ProviderTokenCache,
  sendToDevice,
} from "../_shared/apns.ts";
import { sampleCommute } from "../_shared/commute_sample.ts";
import { checkSpikeToken, json } from "../_shared/guard.ts";

const REQUIRED = ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_P8"] as const;
const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "io.github.swpark3179.weatherbridge";
let tokens: ProviderTokenCache | null = null;

Deno.serve(async (req) => {
  const denied = checkSpikeToken(req, Deno.env.get("SPIKE_TOKEN"));
  if (denied) return denied;
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const missing = REQUIRED.filter((k) => !Deno.env.get(k));
  if (missing.length > 0) {
    return json({ error: "APNs 시크릿 미설정 (docs/setup.md 참고)", missing }, 503);
  }
  tokens ??= new ProviderTokenCache({
    teamId: Deno.env.get("APNS_TEAM_ID")!,
    keyId: Deno.env.get("APNS_KEY_ID")!,
    privateKeyPem: Deno.env.get("APNS_P8")!,
  });

  const input = await req.json().catch(() => ({})) as {
    action?: string;
    env?: ApnsEnv;
    deviceToken?: string;
    channelId?: string;
    minutes?: number;
  };
  const env: ApnsEnv = input.env === "production" ? "production" : "sandbox";
  const now = Math.floor(Date.now() / 1000);
  const providerToken = await tokens.get(now);
  const sample = sampleCommute(now, input.minutes ?? 3);

  try {
    switch (input.action) {
      case "create-channel":
        return json(await createChannel({ env, providerToken, bundleId, storagePolicy: 1 }));

      case "start-sample":
        if (!input.deviceToken) return json({ error: "deviceToken(push-to-start 토큰) 필요" }, 400);
        return json(
          await sendToDevice({
            env,
            providerToken,
            deviceToken: input.deviceToken,
            topic: liveActivityTopic(bundleId),
            pushType: "liveactivity",
            priority: 10,
            payload: buildLiveActivityStart({
              now,
              attributes: sample.attributes,
              state: sample.state,
              alert: { title: "출근 날씨 브리핑", body: sample.state.headline },
              channelId: input.channelId,
            }),
          }),
        );

      case "update-sample":
      case "end-sample": {
        if (!input.channelId) return json({ error: "channelId 필요" }, 400);
        const isEnd = input.action === "end-sample";
        const state = { ...sample.state, headline: isEnd ? "출근 시간입니다" : "업데이트된 샘플" };
        return json(
          await broadcast({
            env,
            providerToken,
            bundleId,
            channelId: input.channelId,
            priority: isEnd ? 10 : 5,
            expiration: 0,
            payload: isEnd
              ? buildLiveActivityEnd({ now, state, dismissalDate: now })
              : buildLiveActivityUpdate({ now, state, staleDate: sample.attributes.windowEnd }),
          }),
        );
      }

      case "send-alert":
        if (!input.deviceToken) return json({ error: "deviceToken(APNs 기기 토큰) 필요" }, 400);
        return json(
          await sendToDevice({
            env,
            providerToken,
            deviceToken: input.deviceToken,
            topic: bundleId,
            pushType: "alert",
            priority: 10,
            payload: { aps: { alert: { title: "WeatherBridge", body: "APNs 테스트 알림" } } },
          }),
        );

      default:
        return json({
          error: "action은 create-channel | start-sample | update-sample | end-sample | send-alert",
        }, 400);
    }
  } catch (e) {
    return json({ error: String(e) }, 502);
  }
});
