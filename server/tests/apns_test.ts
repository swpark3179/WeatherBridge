import { assert, assertEquals, assertNotEquals } from "@std/assert";
import {
  broadcast,
  buildLiveActivityEnd,
  buildLiveActivityStart,
  buildLiveActivityUpdate,
  type CommuteState,
  createChannel,
  createProviderToken,
  type FetchFn,
  liveActivityTopic,
  ProviderTokenCache,
  sendToDevice,
} from "../supabase/functions/_shared/apns.ts";

const FIXTURE = new URL(
  "../../ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/live_activity_start.json",
  import.meta.url,
);

async function testKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const b64 = btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g)!.join("\n");
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`;
  return { pem, publicKey: pair.publicKey };
}

function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

Deno.test("provider token is a valid ES256 JWT", async () => {
  const { pem, publicKey } = await testKey();
  const jwt = await createProviderToken({
    teamId: "TEAM123456",
    keyId: "KEY1234567",
    privateKeyPem: pem,
  }, 1_700_000_000);
  const [h, c, s] = jwt.split(".");
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(h))), {
    alg: "ES256",
    kid: "KEY1234567",
  });
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(c))), {
    iss: "TEAM123456",
    iat: 1_700_000_000,
  });
  const sig = b64urlDecode(s);
  assertEquals(sig.length, 64);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    sig,
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert(valid);
});

Deno.test("provider token accepts a one-line PEM (deploy workflow strips newlines)", async () => {
  const { pem, publicKey } = await testKey();
  const jwt = await createProviderToken({
    teamId: "TEAM123456",
    keyId: "KEY1234567",
    privateKeyPem: pem.replace(/\r?\n/g, ""),
  }, 1_700_000_000);
  const [h, c, s] = jwt.split(".");
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    b64urlDecode(s),
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert(valid);
});

Deno.test("provider token cache reuses token for 50 minutes", async () => {
  const { pem } = await testKey();
  const cache = new ProviderTokenCache({ teamId: "T", keyId: "K", privateKeyPem: pem });
  const first = await cache.get(1000);
  assertEquals(await cache.get(1000 + 49 * 60), first);
  assertNotEquals(await cache.get(1000 + 50 * 60), first);
});

const fixtureState: CommuteState = {
  headline: "☔ 회사 15–18시 최대 70%",
  highlight: true,
  places: [
    {
      name: "집",
      temp: 12,
      pops: [0, 0, 10, 10, 10, 10, 20, 20, 20, 10, 10, 10, 0, 0, 0, 0, 0],
      maxPop: 20,
      rainWindow: null,
    },
    {
      name: "회사",
      temp: 15,
      pops: [0, 0, 10, 10, 20, 30, 40, 50, 60, 70, 60, 40, 20, 10, 0, 0, 0],
      maxPop: 70,
      rainWindow: "15–18시",
    },
  ],
  updatedAt: 1792360800,
};

Deno.test("push-to-start payload matches the iOS contract fixture", async () => {
  const expected = JSON.parse(await Deno.readTextFile(FIXTURE));
  const actual = buildLiveActivityStart({
    now: 1792360800,
    attributes: { windowEnd: 1792364400, firstHour: 7 },
    state: fixtureState,
    alert: { title: "출근 날씨 브리핑", body: fixtureState.headline },
    channelId: "dHN0LXNyY2gtY2hubA==",
  });
  assertEquals(actual, expected);
});

Deno.test("push-to-start omits input-push-channel without a channel", () => {
  const payload = buildLiveActivityStart({
    now: 1,
    attributes: { windowEnd: 100, firstHour: 7 },
    state: fixtureState,
    alert: { title: "t", body: "b" },
  });
  assert(!("input-push-channel" in payload.aps));
  assertEquals(payload.aps["stale-date"], 100);
});

Deno.test("update and end payloads", () => {
  const update = buildLiveActivityUpdate({ now: 10, state: fixtureState, staleDate: 99 });
  assertEquals(update.aps.event, "update");
  assertEquals(update.aps["stale-date"], 99);
  const end = buildLiveActivityEnd({ now: 10, state: fixtureState, dismissalDate: 10 });
  assertEquals(end.aps.event, "end");
  assertEquals(end.aps["dismissal-date"], 10);
});

function recordingFetch(response: Response) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn: FetchFn = (url, init) => {
    calls.push({ url, init });
    return Promise.resolve(response);
  };
  return { fn, calls };
}

Deno.test("sendToDevice builds a Live Activity request", async () => {
  const { fn, calls } = recordingFetch(
    new Response(null, { status: 200, headers: { "apns-id": "abc" } }),
  );
  const res = await sendToDevice({
    env: "sandbox",
    providerToken: "jwt",
    deviceToken: "deadbeef",
    topic: liveActivityTopic("io.github.swpark3179.weatherbridge"),
    pushType: "liveactivity",
    priority: 10,
    payload: { aps: {} },
  }, fn);
  assertEquals(res, { status: 200, apnsId: "abc", channelId: null, body: null });
  assertEquals(calls[0].url, "https://api.sandbox.push.apple.com/3/device/deadbeef");
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers["apns-topic"], "io.github.swpark3179.weatherbridge.push-type.liveactivity");
  assertEquals(headers["apns-push-type"], "liveactivity");
  assertEquals(headers.authorization, "bearer jwt");
});

Deno.test("createChannel reads apns-channel-id", async () => {
  const { fn, calls } = recordingFetch(
    new Response(null, { status: 201, headers: { "apns-channel-id": "Y2hhbm5lbA==" } }),
  );
  const res = await createChannel({
    env: "sandbox",
    providerToken: "jwt",
    bundleId: "io.github.swpark3179.weatherbridge",
    storagePolicy: 1,
  }, fn);
  assertEquals(res.status, 201);
  assertEquals(res.channelId, "Y2hhbm5lbA==");
  assertEquals(
    calls[0].url,
    "https://api-manage-broadcast.sandbox.push.apple.com:2195/1/apps/io.github.swpark3179.weatherbridge/channels",
  );
  assertEquals(JSON.parse(calls[0].init.body as string), {
    "message-storage-policy": 1,
    "push-type": "LiveActivity",
  });
});

Deno.test("broadcast sends to the channel endpoint with required headers", async () => {
  const { fn, calls } = recordingFetch(
    new Response(JSON.stringify({ reason: "BadChannelId" }), { status: 400 }),
  );
  const res = await broadcast({
    env: "production",
    providerToken: "jwt",
    bundleId: "b",
    channelId: "c",
    priority: 5,
    expiration: 0,
    payload: { aps: {} },
  }, fn);
  assertEquals(res.body, { reason: "BadChannelId" });
  assertEquals(calls[0].url, "https://api-broadcast.push.apple.com/4/broadcasts/apps/b");
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers["apns-channel-id"], "c");
  assertEquals(headers["apns-priority"], "5");
  assertEquals(headers["apns-expiration"], "0");
  assertEquals(headers["apns-push-type"], "liveactivity");
});
