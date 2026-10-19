import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { MemoryRepo, type Place } from "../supabase/functions/_shared/db.ts";
import {
  type ApnsConfig,
  MAX_ATTEMPTS,
  runDispatch,
  summaryPayload,
} from "../supabase/functions/_shared/dispatch.ts";
import { kst, openMeteoBody, routedFetch } from "./fixtures.ts";

const H = 3600;
const USER = "11111111-aaaa-bbbb-cccc-000000000001";
const TOKEN = "ab".repeat(32);

async function apnsConfig(): Promise<ApnsConfig> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  return {
    key: {
      teamId: "TEAM123456",
      keyId: "KEY1234567",
      privateKeyPem: `-----BEGIN PRIVATE KEY-----${
        btoa(String.fromCharCode(...pkcs8))
      }-----END PRIVATE KEY-----`,
    },
    bundleId: "io.github.swpark3179.weatherbridge",
  };
}

function place(kind: "home" | "office", name: string): Place {
  return {
    id: `${kind}-1`,
    userId: USER,
    kind,
    name,
    lat: 37.57,
    lon: 126.98,
    tz: "Asia/Seoul",
    kmaNx: 60,
    kmaNy: 127,
  };
}

function setup() {
  const repo = new MemoryRepo();
  repo.places = [place("home", "집"), place("office", "회사")];
  repo.settings = [{
    userId: USER,
    tz: "Asia/Seoul",
    summaryEnabled: true,
    summaryTime: "07:00",
    threshold: 30,
  }];
  repo.devices = [{
    id: "device-1",
    userId: USER,
    apnsToken: TOKEN,
    apnsEnv: "production",
    active: true,
    reason: null,
  }];
  return repo;
}

/** 예보(Open-Meteo만)와 APNs 응답을 흉내 낸다. apnsStatuses는 차례로 돌려줄 상태 코드. */
function fakes(apnsStatuses: Array<number | [number, string]>) {
  const t0 = kst(2026, 10, 20, 7);
  const times = Array.from({ length: 18 }, (_, i) => t0 + i * H);
  const forecast = routedFetch([
    [/open-meteo/, () =>
      openMeteoBody(times, {
        ecmwf_ifs025: times.map((_, i) => (i >= 8 && i < 11 ? 80 : 10)),
        ncep_gfs_seamless: times.map((_, i) => (i >= 8 && i < 11 ? 70 : 0)),
        dwd_icon_seamless: times.map(() => 10),
      })],
  ]);
  const apnsCalls: Array<{ url: string; headers: Record<string, string>; body: unknown }> = [];
  const apnsFetch = (url: string, init: RequestInit) => {
    apnsCalls.push({
      url,
      headers: init.headers as Record<string, string>,
      body: JSON.parse(String(init.body)),
    });
    const next = apnsStatuses.shift() ?? 200;
    const [status, reason] = Array.isArray(next) ? next : [next, undefined];
    return Promise.resolve(
      new Response(reason ? JSON.stringify({ reason }) : null, {
        status,
        headers: { "apns-id": crypto.randomUUID() },
      }),
    );
  };
  return { forecastFetch: forecast.fn, apnsFetch, apnsCalls };
}

function deps(
  repo: MemoryRepo,
  nowSec: number,
  fetchFn: ReturnType<typeof fakes>["forecastFetch"],
) {
  repo.clock = () => nowSec;
  return { repo, nowMs: () => nowSec * 1000, fetchFn };
}

Deno.test("sends the summary once at the scheduled minute", async () => {
  const repo = setup();
  const apns = await apnsConfig();
  const f = fakes([200]);
  const at = kst(2026, 10, 20, 7, 0);

  const first = await runDispatch(deps(repo, at, f.forecastFetch), {
    apns,
    apnsFetch: f.apnsFetch,
  });
  assertEquals([first.due, first.sent, first.errors], [1, 1, []]);
  assertEquals(f.apnsCalls.length, 1);
  const call = f.apnsCalls[0];
  assertEquals(call.url, `https://api.push.apple.com/3/device/${TOKEN}`);
  assertEquals(call.headers["apns-topic"], "io.github.swpark3179.weatherbridge");
  assertEquals(call.headers["apns-push-type"], "alert");
  assertEquals(call.headers["apns-collapse-id"], "summary-2026-10-20");
  const aps = (call.body as { aps: { alert: { title: string; body: string } } }).aps;
  assertEquals(aps.alert.title, "☔ 오늘 비 소식이 있어요");
  // Open-Meteo는 "직전 1시간" 라벨이라 15–17시 값이 14–16시 슬롯이 된다
  assert(aps.alert.body.startsWith("집 ☔ 14–17시"), aps.alert.body);
  assertEquals(repo.dispatches.map((d) => [d.localDate, d.status, d.attempts]), [
    ["2026-10-20", "sent", 1],
  ]);

  // 다음 분: 이미 보냈으므로 아무것도 하지 않는다
  const again = await runDispatch(deps(repo, at + 60, f.forecastFetch), {
    apns,
    apnsFetch: f.apnsFetch,
  });
  assertEquals([again.due, again.sent], [1, 0]);
  assertEquals(f.apnsCalls.length, 1);
});

Deno.test("does nothing before the scheduled time or after the window", async () => {
  const repo = setup();
  const apns = await apnsConfig();
  const f = fakes([]);
  for (const t of [kst(2026, 10, 20, 6, 59), kst(2026, 10, 20, 7, 15)]) {
    const r = await runDispatch(deps(repo, t, f.forecastFetch), { apns, apnsFetch: f.apnsFetch });
    assertEquals([r.candidates, r.due], [1, 0]);
  }
  assertEquals(repo.dispatches, []);
  assertEquals(f.apnsCalls.length, 0);
});

Deno.test("retries a temporary APNs failure on the next minute", async () => {
  const repo = setup();
  const apns = await apnsConfig();
  const f = fakes([503, 200]);
  const at = kst(2026, 10, 20, 7, 0);

  const first = await runDispatch(deps(repo, at, f.forecastFetch), {
    apns,
    apnsFetch: f.apnsFetch,
  });
  assertEquals(first.retry, 1);
  assertEquals(repo.dispatches[0].status, "retry");

  const second = await runDispatch(deps(repo, at + 60, f.forecastFetch), {
    apns,
    apnsFetch: f.apnsFetch,
  });
  assertEquals(second.sent, 1);
  assertEquals([repo.dispatches[0].status, repo.dispatches[0].attempts], ["sent", 2]);
});

Deno.test("gives up after the maximum attempts", async () => {
  const repo = setup();
  const apns = await apnsConfig();
  const f = fakes(Array(MAX_ATTEMPTS).fill(500));
  const at = kst(2026, 10, 20, 7, 0);
  for (let i = 0; i < MAX_ATTEMPTS + 1; i++) {
    await runDispatch(deps(repo, at + i * 60, f.forecastFetch), { apns, apnsFetch: f.apnsFetch });
  }
  assertEquals(f.apnsCalls.length, MAX_ATTEMPTS);
  assertEquals([repo.dispatches[0].status, repo.dispatches[0].attempts], ["failed", MAX_ATTEMPTS]);
});

Deno.test("deactivates a device APNs reports as unregistered", async () => {
  const repo = setup();
  const apns = await apnsConfig();
  const f = fakes([[410, "Unregistered"]]);
  const r = await runDispatch(deps(repo, kst(2026, 10, 20, 7), f.forecastFetch), {
    apns,
    apnsFetch: f.apnsFetch,
  });
  assertEquals(r.failed, 1);
  assertEquals([repo.devices[0].active, repo.devices[0].reason], [false, "410 Unregistered"]);
});

Deno.test("renews the provider token once when APNs says it expired", async () => {
  const repo = setup();
  const apns = await apnsConfig();
  const at = kst(2026, 10, 20, 7);
  // 40분 전에 만든 토큰이 저장돼 있지만 APNs가 만료로 거부한다
  repo.providerTokens.set("KEY1234567", { token: "old-token", issuedAt: at - 40 * 60 });
  const f = fakes([[403, "ExpiredProviderToken"], 200]);
  const r = await runDispatch(deps(repo, at, f.forecastFetch), { apns, apnsFetch: f.apnsFetch });
  assertEquals(r.sent, 1);
  assertEquals(f.apnsCalls.map((c) => c.headers.authorization.slice(0, 16)), [
    "bearer old-token",
    f.apnsCalls[1].headers.authorization.slice(0, 16),
  ]);
  assertNotEquals(f.apnsCalls[1].headers.authorization, "bearer old-token");
  assertEquals(repo.providerTokens.get("KEY1234567")?.issuedAt, at);
});

Deno.test("reuses the stored provider token across runs", async () => {
  const repo = setup();
  repo.settings.push({ ...repo.settings[0], userId: "user-2", summaryTime: "07:01" });
  repo.devices.push({
    ...repo.devices[0],
    id: "device-2",
    userId: "user-2",
    apnsToken: "cd".repeat(32),
  });
  repo.places.push(...repo.places.map((p) => ({ ...p, id: `${p.id}-2`, userId: "user-2" })));
  const apns = await apnsConfig();
  const f = fakes([200, 200]);
  const at = kst(2026, 10, 20, 7, 0);
  await runDispatch(deps(repo, at, f.forecastFetch), { apns, apnsFetch: f.apnsFetch });
  await runDispatch(deps(repo, at + 60, f.forecastFetch), { apns, apnsFetch: f.apnsFetch });
  assertEquals(f.apnsCalls.length, 2);
  assertEquals(f.apnsCalls[0].headers.authorization, f.apnsCalls[1].headers.authorization);
  assertEquals(repo.providerTokens.get("KEY1234567")?.issuedAt, at);
});

Deno.test("skips users without devices and reports missing APNs keys without claiming", async () => {
  const repo = setup();
  repo.devices = [];
  const f = fakes([]);
  const at = kst(2026, 10, 20, 7);
  const noKeys = await runDispatch(deps(repo, at, f.forecastFetch), { apns: null });
  assertEquals(noKeys.errors.length, 1);
  assertEquals(repo.dispatches, []);

  const r = await runDispatch(deps(repo, at, f.forecastFetch), {
    apns: await apnsConfig(),
    apnsFetch: f.apnsFetch,
  });
  assertEquals(r.skipped, 1);
  assertEquals(repo.dispatches[0].status, "skipped");
  assertEquals(repo.dispatches[0].detail, { reason: "no_devices" });
});

Deno.test("dry run counts due users and previews one user's alert without side effects", async () => {
  const repo = setup();
  const f = fakes([]);
  const r = await runDispatch(deps(repo, kst(2026, 10, 20, 7, 3), f.forecastFetch), {
    apns: null,
    dryRun: true,
    userId: USER,
  });
  assertEquals([r.dryRun, r.candidates, r.due], [true, 1, 1]);
  assertEquals(r.previews.length, 1);
  assertEquals(r.previews[0].user, USER.slice(0, 8));
  assertEquals(r.previews[0].localDate, "2026-10-20");
  assertEquals(repo.dispatches, []);
  assertEquals(f.apnsCalls.length, 0);
});

Deno.test("dry run previews a user who has not turned summaries on", async () => {
  const repo = setup();
  repo.settings = [];
  const f = fakes([]);
  const r = await runDispatch(deps(repo, kst(2026, 10, 20, 9), f.forecastFetch), {
    apns: null,
    dryRun: true,
    userId: USER,
  });
  assertEquals(r.candidates, 0);
  assertEquals(r.previews[0].localDate, null);
  assert(r.previews[0].payload !== null);
});

Deno.test("summary payload has no-rain wording when nothing is highlighted", () => {
  const payload = summaryPayload({
    state: { headline: "오늘 비 소식 없음 (최대 10%)", highlight: false, places: [], updatedAt: 0 },
    firstHour: 7,
    summary: "집 비 소식 없음(최대 10%)",
  }, "2026-10-20");
  assertEquals(payload.aps.alert, {
    title: "오늘은 비 소식이 없어요",
    body: "집 비 소식 없음(최대 10%)",
  });
  assertEquals(payload.localDate, "2026-10-20");
});
