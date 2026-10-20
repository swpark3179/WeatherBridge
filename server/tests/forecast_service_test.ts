import { assert, assertEquals } from "@std/assert";
import { MemoryRepo, type Place } from "../supabase/functions/_shared/db.ts";
import { ensureForecasts, refreshAll } from "../supabase/functions/_shared/forecast_service.ts";
import { kmaNcstBody, kmaVilageBody, kst, openMeteoBody, routedFetch } from "./fixtures.ts";

const NOW = kst(2026, 10, 19, 7, 20); // 05시 발표가 최신, 06시 실황
const H = 3600;

function place(overrides: Partial<Place> = {}): Place {
  return {
    id: crypto.randomUUID(),
    userId: null,
    kind: "home",
    name: "집",
    lat: 37.57,
    lon: 126.98,
    tz: "Asia/Seoul",
    kmaNx: null,
    kmaNy: null,
    ...overrides,
  };
}

function apis() {
  const t0 = kst(2026, 10, 19, 7);
  const times = Array.from({ length: 6 }, (_, i) => t0 + i * H);
  return routedFetch([
    [
      /getVilageFcst/,
      () => kmaVilageBody(kst(2026, 10, 19, 5), times.map((t) => ({ t, pop: 30 }))),
    ],
    [/getUltraSrtNcst/, () => kmaNcstBody(kst(2026, 10, 19, 6), { RN1: "0", PTY: "0", T1H: "11" })],
    [
      /open-meteo/,
      () =>
        openMeteoBody(times, {
          ecmwf_ifs025: [10, 20, 30, 40, 50, 60],
          ncep_gfs_seamless: [0, 0, 10, 10, 20, 20],
          dwd_icon_seamless: [0, 10, 10, 20, 20, 30],
        }),
    ],
  ]);
}

function deps(
  repo: MemoryRepo,
  fetchFn: ReturnType<typeof apis>["fn"],
  nowSec = NOW,
  opts: { kmaServiceKey?: string } = { kmaServiceKey: "k" },
) {
  return { repo, nowMs: () => nowSec * 1000, kmaServiceKey: opts.kmaServiceKey, fetchFn };
}

Deno.test("first refresh fetches, caches, logs and stores the grid", async () => {
  const repo = new MemoryRepo();
  repo.places = [place()];
  const { fn, calls } = apis();

  const summary = await refreshAll(deps(repo, fn));

  assertEquals(summary.errors, []);
  assertEquals(summary.fetched.sort(), [
    "kma_short@home",
    "om_ecmwf@home",
    "om_gfs@home",
    "om_icon@home",
  ]);
  assertEquals(summary.logged, 4);
  assertEquals(summary.observations, 1);
  assertEquals(repo.places[0].kmaNx, 60);
  assertEquals(repo.places[0].kmaNy, 127);
  assertEquals(repo.cache.size, 4);
  assertEquals(calls.filter((c) => c.includes("open-meteo")).length, 1); // 3개 모델을 한 번에
  // 기록은 POP가 있는 슬롯만, 72시간 이내
  const kmaLog = repo.logs.find((l) => l.provider === "kma_short")!;
  assertEquals(kmaLog.locKey, "kma:60:127");
  assertEquals(kmaLog.issuedAt, kst(2026, 10, 19, 5));
  assertEquals(kmaLog.slots.length, 6);
  // Open-Meteo 기록은 기상청 발표 주기(05시)에 맞춘다
  assertEquals(repo.logs.find((l) => l.provider === "om_ecmwf")!.issuedAt, kst(2026, 10, 19, 5));
  assertEquals([...repo.observations.values()][0].t1h, 11);
});

Deno.test("refresh within cache lifetime does not refetch forecasts or duplicate logs", async () => {
  const repo = new MemoryRepo();
  repo.places = [place()];
  const first = apis();
  await refreshAll(deps(repo, first.fn));

  const second = apis();
  const summary = await refreshAll(deps(repo, second.fn, NOW + 10 * 60));
  assertEquals(summary.fetched, []);
  assertEquals(summary.logged, 0);
  assertEquals(second.calls.filter((c) => !c.includes("getUltraSrtNcst")), []);
  assertEquals(repo.logs.length, 4);
});

Deno.test("expired caches refetch: Open-Meteo hourly, KMA only after the next publish", async () => {
  const repo = new MemoryRepo();
  repo.places = [place()];
  const start = kst(2026, 10, 19, 5, 20); // 05시 발표 → 다음은 08:15
  await refreshAll(deps(repo, apis().fn, start));

  const hourLater = apis();
  await refreshAll(deps(repo, hourLater.fn, start + H));
  assert(hourLater.calls.some((c) => c.includes("open-meteo")));
  assert(!hourLater.calls.some((c) => c.includes("getVilageFcst")));

  const afterPublish = apis();
  await refreshAll(deps(repo, afterPublish.fn, kst(2026, 10, 19, 8, 16)));
  assert(afterPublish.calls.some((c) => c.includes("getVilageFcst")));
});

Deno.test("without a KMA key only Open-Meteo is used", async () => {
  const repo = new MemoryRepo();
  repo.places = [place()];
  const { fn, calls } = apis();
  const summary = await refreshAll(deps(repo, fn, NOW, {}));
  assertEquals(summary.logged, 3);
  assertEquals(summary.observations, 0);
  assert(!calls.some((c) => c.includes("data.go.kr")));
});

Deno.test("overseas places skip KMA even with a key", async () => {
  const repo = new MemoryRepo();
  const tokyo = place({ kind: "trip", name: "도쿄", lat: 35.68, lon: 139.65, tz: "Asia/Tokyo" });
  const { fn, calls } = apis();
  const result = await ensureForecasts(tokyo, deps(repo, fn));
  assertEquals(result.forecasts.map((f) => f.provider), ["om_ecmwf", "om_gfs", "om_icon"]);
  assert(!calls.some((c) => c.includes("data.go.kr")));
});

Deno.test("home and office in the same cell share fetches and logs", async () => {
  const repo = new MemoryRepo();
  repo.places = [place(), place({ kind: "office", name: "회사" })];
  const { fn, calls } = apis();
  const summary = await refreshAll(deps(repo, fn));
  assertEquals(calls.filter((c) => c.includes("open-meteo")).length, 1);
  assertEquals(calls.filter((c) => c.includes("getVilageFcst")).length, 1);
  assertEquals(summary.logged, 4);
  assertEquals(summary.observations, 1);
});

Deno.test("a failing source keeps the stale cache and reports the error", async () => {
  const repo = new MemoryRepo();
  const home = place();
  repo.places = [home];
  await refreshAll(deps(repo, apis().fn, kst(2026, 10, 19, 6, 0)));

  const failing = routedFetch([
    [
      /open-meteo/,
      () =>
        new Response(JSON.stringify({ error: true, reason: "Too many requests" }), { status: 429 }),
    ],
  ]);
  // 기상청 캐시는 08:15까지 유효, Open-Meteo는 06:55에 만료
  const result = await ensureForecasts(home, deps(repo, failing.fn, kst(2026, 10, 19, 7, 0)));
  assertEquals(result.errors.length, 1);
  assert(result.errors[0].includes("Too many requests"));
  assertEquals(result.forecasts.map((f) => f.provider).sort(), [
    "kma_short",
    "om_ecmwf",
    "om_gfs",
    "om_icon",
  ]);
});
