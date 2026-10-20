import { assert, assertEquals } from "@std/assert";
import type { Place } from "../supabase/functions/_shared/db.ts";
import { MemoryRepo } from "../supabase/functions/_shared/db.ts";
import type { ProviderForecast, ProviderId } from "../supabase/functions/_shared/forecast_types.ts";
import { PROVIDER_FAMILY } from "../supabase/functions/_shared/forecast_types.ts";
import {
  buildToday,
  type LoadedPlace,
  loadForecasts,
} from "../supabase/functions/_shared/today.ts";
import { kst, openMeteoBody, routedFetch } from "./fixtures.ts";

const FIXTURE = new URL(
  "../../ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/today_response.json",
  import.meta.url,
);
const H = 3600;
const T0 = kst(2026, 10, 20, 6);
const NOW = kst(2026, 10, 20, 6, 10);

function place(kind: "home" | "office", name: string): Place {
  return {
    id: `${kind}-id`,
    userId: "user-1",
    kind,
    name,
    lat: 37.57,
    lon: 126.98,
    tz: "Asia/Seoul",
    kmaNx: 60,
    kmaNy: 127,
  };
}

function fc(provider: ProviderId, pops: number[], temps: number[] = []): ProviderForecast {
  return {
    provider,
    family: PROVIDER_FAMILY[provider],
    issuedAt: kst(2026, 10, 20, 5),
    fetchedAt: kst(2026, 10, 20, 5, 20),
    slots: pops.map((pop, i) => ({
      t: T0 + i * H,
      pop,
      span: 1,
      precipMm: pop >= 50 ? 1 : 0,
      temp: temps[i] ?? null,
    })),
  };
}

/** 계약 샘플용 입력: 집은 08–10시 비, 회사는 비 소식 없음, 06시부터 4시간 */
function sample(): LoadedPlace[] {
  return [
    {
      place: place("home", "집"),
      forecasts: [
        fc("kma_short", [10, 20, 60, 70], [15, 16, 17, 17]),
        fc("om_ecmwf", [5, 30, 80, 90], [14.6, 15.2, 16.1, 16.4]),
        fc("om_gfs", [0, 10, 40, 60]),
        fc("om_icon", [0, 0, 20, 50]),
      ],
      errors: [],
    },
    {
      place: place("office", "회사"),
      forecasts: [
        fc("kma_short", [0, 0, 10, 10], [14, 15, 16, 16]),
        fc("om_ecmwf", [0, 5, 10, 15]),
        fc("om_gfs", [0, 0, 0, 0]),
      ],
      errors: ["om_icon: timeout"],
    },
  ];
}

Deno.test("today response matches the shared Swift contract fixture", async () => {
  const actual = buildToday(sample(), {
    nowSec: NOW,
    tz: "Asia/Seoul",
    threshold: 30,
    horizonHours: 4,
  });
  const json = JSON.stringify(actual, null, 2) + "\n";

  // 샘플을 다시 만들 때: deno task fixtures
  const env = Deno.permissions.querySync({ name: "env", variable: "UPDATE_FIXTURES" });
  if (env.state === "granted" && Deno.env.get("UPDATE_FIXTURES") === "1") {
    await Deno.writeTextFile(FIXTURE, json);
  }
  assertEquals(JSON.parse(await Deno.readTextFile(FIXTURE)), JSON.parse(json));
});

Deno.test("today response carries per-hour family and source values but no coordinates", () => {
  const r = buildToday(sample(), { nowSec: NOW, tz: "Asia/Seoul", threshold: 30, horizonHours: 4 });
  const home = r.places[0];
  assertEquals(home.kind, "home");
  assertEquals(home.hours.length, 4);
  assertEquals(home.hours[2].providers, { kma_short: 60, om_ecmwf: 80, om_gfs: 40, om_icon: 20 });
  assertEquals(home.hours[2].families, { kma: 60, ecmwf: 80, ncep: 40, dwd: 20 });
  // 07시는 종합 16%라 비 시간이 아니다
  assertEquals(home.windows.map((w) => [w.start, w.end]), [[T0 + 2 * H, T0 + 4 * H]]);
  assertEquals(r.places[1].errors, ["om_icon: timeout"]);
  assert(r.briefing.state.highlight);
  const text = JSON.stringify(r);
  assert(!text.includes("lat") && !text.includes("37.57"), "좌표가 응답에 있으면 안 된다");
});

Deno.test("the user's threshold changes the rain window", () => {
  const loose = buildToday(sample(), {
    nowSec: NOW,
    tz: "Asia/Seoul",
    threshold: 10,
    horizonHours: 4,
  });
  // 임계값 10%면 07시(종합 16%)부터 비 시간이다
  assertEquals(loose.places[0].windows.map((w) => [w.start, w.end]), [[T0 + H, T0 + 4 * H]]);
  assertEquals(loose.threshold, 10);
});

Deno.test("loadForecasts returns home before office and uses the cache path", async () => {
  const repo = new MemoryRepo();
  const times = Array.from({ length: 3 }, (_, i) => T0 + i * H);
  const { fn, calls } = routedFetch([
    [/open-meteo/, () =>
      openMeteoBody(times, {
        ecmwf_ifs025: [10, 20, 30],
        ncep_gfs_seamless: [0, 10, 20],
        dwd_icon_seamless: [0, 0, 10],
      })],
  ]);
  const deps = { repo, nowMs: () => NOW * 1000, fetchFn: fn };
  const loaded = await loadForecasts(deps, [place("office", "회사"), place("home", "집")]);
  assertEquals(loaded.map((l) => l.place.kind), ["home", "office"]);
  // 같은 좌표라 두 번째 장소는 캐시를 쓴다
  assertEquals(calls.length, 1);
  assertEquals(loaded[1].forecasts.length, 3);
});
