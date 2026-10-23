import { assert, assertEquals } from "@std/assert";
import { MemoryRepo, type Place, type Trip } from "../supabase/functions/_shared/db.ts";
import type {
  HourSlot,
  ProviderForecast,
  ProviderId,
} from "../supabase/functions/_shared/forecast_types.ts";
import { PROVIDER_FAMILY } from "../supabase/functions/_shared/forecast_types.ts";
import { addDays, parseLocalDate, zonedEpoch } from "../supabase/functions/_shared/schedule.ts";
import {
  buildTrips,
  type LoadedTrips,
  loadTripForecasts,
} from "../supabase/functions/_shared/trips.ts";
import { kst, openMeteoBody, routedFetch } from "./fixtures.ts";

const FIXTURE = new URL(
  "../../ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/trips_response.json",
  import.meta.url,
);
const H = 3600;
/** 서울 10/20 06:10 = 콜카타 10/20 02:40 = 삿포로 10/20 06:10 = 호놀룰루 10/19 11:10 */
const NOW = kst(2026, 10, 20, 6, 10);
const OPTS = { nowSec: NOW, threshold: 30 };

/** 모델마다 조금씩 다른 치우침: 앱이 같은 모델끼리 비교해야 차이에서 빠진다 */
const BIAS: Record<ProviderId, number> = { kma_short: 0, om_ecmwf: 0, om_gfs: 1, om_icon: -0.6 };

interface DaySpec {
  high: number;
  low: number;
  pop: number;
  cloud?: number;
  /** 하루 적설(cm). 시간마다 고르게 나눈다 */
  snowCm?: number;
}

/** 현지 시각에 따라 03시 최저, 15시 최고 */
function tempAt(spec: DaySpec, hour: number): number {
  const mid = (spec.high + spec.low) / 2;
  const amp = (spec.high - spec.low) / 2;
  return mid + amp * Math.sin((2 * Math.PI * (hour - 9)) / 24);
}

const round1 = (v: number) => Math.round(v * 10) / 10;

/** 날짜별 모양으로 시간별 예보를 만든다. 날짜를 빼면 그 모델이 거기까지 닿지 않는 것 */
function forecast(
  provider: ProviderId,
  tz: string,
  days: Array<[string, DaySpec]>,
): ProviderForecast {
  const slots: HourSlot[] = [];
  for (const [date, spec] of days) {
    const local = parseLocalDate(date);
    const start = zonedEpoch(local, 0, 0, tz);
    const end = zonedEpoch(addDays(local, 1), 0, 0, tz);
    for (let t = Math.ceil(start / H) * H; t < end; t += H) {
      const hour = (t - start) / H;
      slots.push({
        t,
        pop: spec.pop,
        span: 1,
        precipMm: spec.pop >= 50 ? 1 : 0,
        temp: round1(tempAt(spec, hour) + BIAS[provider]),
        ...(provider === "kma_short" ? {} : {
          cloud: spec.cloud ?? null,
          snowCm: round1((spec.snowCm ?? 0) / 24),
        }),
      });
    }
  }
  return {
    provider,
    family: PROVIDER_FAMILY[provider],
    issuedAt: kst(2026, 10, 20, 5),
    fetchedAt: kst(2026, 10, 20, 5, 20),
    slots,
  };
}

function place(id: string, name: string, tz: string, kind: Place["kind"] = "trip"): Place {
  return {
    id,
    userId: "user-1",
    kind,
    name,
    lat: 35.0,
    lon: 135.0,
    tz,
    kmaNx: null,
    kmaNy: null,
  };
}

function trip(id: string, dest: Place, startDate: string, endDate: string): Trip {
  return { id, userId: "user-1", place: dest, startDate, endDate };
}

const SEOUL: Array<[string, DaySpec]> = [
  ["2026-10-17", { high: 21, low: 11, pop: 10, cloud: 20 }],
  ["2026-10-18", { high: 20, low: 10, pop: 10, cloud: 30 }],
  ["2026-10-19", { high: 19, low: 9, pop: 10, cloud: 40 }],
  ["2026-10-20", { high: 18, low: 9, pop: 20, cloud: 50 }],
  ["2026-10-21", { high: 19, low: 10, pop: 10, cloud: 30 }],
  ["2026-10-22", { high: 20, low: 11, pop: 10, cloud: 20 }],
  ["2026-10-23", { high: 21, low: 12, pop: 10, cloud: 40 }],
  ["2026-10-24", { high: 15, low: 6, pop: 40, cloud: 80 }],
];

const SAPPORO: Array<[string, DaySpec]> = [
  ["2026-10-22", { high: 15, low: 6, pop: 10, cloud: 30 }],
  ["2026-10-23", { high: 16, low: 7, pop: 10, cloud: 20 }],
  ["2026-10-24", { high: 3, low: -2, pop: 80, cloud: 95, snowCm: 3 }],
];

const KOLKATA: Array<[string, DaySpec]> = [
  ["2026-10-19", { high: 31, low: 25, pop: 30, cloud: 50 }],
  ["2026-10-20", { high: 32, low: 25, pop: 35, cloud: 50 }],
  ["2026-10-21", { high: 32, low: 26, pop: 20, cloud: 40 }],
];

/** ICON은 6일 뒤(10/24)에 닿지 않는다 */
const upTo23 = (days: Array<[string, DaySpec]>) => days.filter(([d]) => d <= "2026-10-23");

const HOME = place("home-id", "집", "Asia/Seoul", "home");
const SAPPORO_PLACE = place("sapporo-id", "삿포로", "Asia/Tokyo");
const KOLKATA_PLACE = place("kolkata-id", "콜카타", "Asia/Kolkata");

/**
 * 계약 샘플용 입력 (서울 10/20 06:10).
 * - 삿포로 10/23–24: 다가오는 여행. 10/24는 ICON이 닿지 않아 2개 모델, 눈.
 * - 콜카타 10/19–20: 여행 중(+5:30이라 현지 자정이 정시가 아니다). 10/19는 두 곳 모두 지나 빠진다.
 * - 파리 11/14–15: 16일보다 멀어 예보 없음. 제주 10/10–12: 끝난 여행.
 * - 집은 10/17부터 값이 있어 지난 기온이 10/17–10/20이다. 기상청은 10/22까지.
 */
function sample(): LoadedTrips {
  return {
    home: HOME,
    homeForecasts: [
      forecast(
        "kma_short",
        "Asia/Seoul",
        SEOUL.filter(([d]) => d >= "2026-10-20" && d <= "2026-10-22"),
      ),
      forecast("om_ecmwf", "Asia/Seoul", SEOUL),
      forecast("om_gfs", "Asia/Seoul", SEOUL),
      forecast("om_icon", "Asia/Seoul", upTo23(SEOUL)),
    ],
    trips: [
      trip("jeju", place("jeju-id", "제주", "Asia/Seoul"), "2026-10-10", "2026-10-12"),
      trip("paris", place("paris-id", "파리", "Europe/Paris"), "2026-11-14", "2026-11-15"),
      trip("sapporo", SAPPORO_PLACE, "2026-10-23", "2026-10-24"),
      trip("kolkata", KOLKATA_PLACE, "2026-10-19", "2026-10-20"),
    ],
    destinations: new Map([
      ["sapporo", [
        forecast("om_ecmwf", "Asia/Tokyo", SAPPORO),
        forecast("om_gfs", "Asia/Tokyo", SAPPORO),
        forecast("om_icon", "Asia/Tokyo", upTo23(SAPPORO)),
      ]],
      ["kolkata", [
        forecast("om_ecmwf", "Asia/Kolkata", KOLKATA),
        forecast("om_gfs", "Asia/Kolkata", KOLKATA),
        forecast("om_icon", "Asia/Kolkata", KOLKATA),
      ]],
    ]),
  };
}

Deno.test("trips response matches the shared Swift contract fixture", async () => {
  const json = JSON.stringify(buildTrips(sample(), OPTS), null, 2) + "\n";

  // 샘플을 다시 만들 때: deno task fixtures
  const env = Deno.permissions.querySync({ name: "env", variable: "UPDATE_FIXTURES" });
  if (env.state === "granted" && Deno.env.get("UPDATE_FIXTURES") === "1") {
    await Deno.writeTextFile(FIXTURE, json);
  }
  assertEquals(JSON.parse(await Deno.readTextFile(FIXTURE)), JSON.parse(json));
});

Deno.test("trips are ordered ongoing, upcoming, then ended; far trips carry no weather", () => {
  const res = buildTrips(sample(), OPTS);
  assertEquals(res.trips.map((t) => [t.id, t.watched]), [
    ["kolkata", true],
    ["sapporo", true],
    ["paris", false],
    ["jeju", false],
  ]);
  const paris = res.trips[2];
  assertEquals(paris.days.map((d) => d.date), ["2026-11-14", "2026-11-15"]);
  assert(paris.days.every((d) => d.destination === null && d.home === null));
  assertEquals(res.trips[3].days, []);
});

Deno.test("each place splits days at its own midnight, including half-hour zones", () => {
  const kolkata = buildTrips(sample(), OPTS).trips[0];
  // 10/19는 서울·콜카타 모두 지났다
  assertEquals(kolkata.days.map((d) => d.date), ["2026-10-20"]);
  const day = kolkata.days[0];
  const istMidnight = Date.UTC(2026, 9, 19, 18, 30) / 1000;
  assertEquals(day.destination!.start, istMidnight);
  // 시간별 기온은 UTC 정시라 00:30부터
  assertEquals(day.destination!.temps!.start, istMidnight + 30 * 60);
  assertEquals(day.destination!.temps!.temps.length, 24);
  assertEquals(day.home!.start, kst(2026, 10, 20, 0));
  // 비는 지금 시간부터: 10/20 콜카타는 3개 모델 모두 35%
  assertEquals(day.destination!.rain, { pop: 35, agreeing: 3, total: 3, rainy: true });
});

Deno.test("far days use only the models that reach the whole day", () => {
  const sapporo = buildTrips(sample(), OPTS).trips[1];
  const [d23, d24] = sapporo.days;
  assertEquals(d23.destination!.temps!.providers, ["om_ecmwf", "om_gfs", "om_icon"]);
  assertEquals(d24.destination!.temps!.providers, ["om_ecmwf", "om_gfs"]);
  assertEquals(d24.home!.temps!.providers, ["om_ecmwf", "om_gfs"]);
  // 비 소식도 그 날 끝까지 닿는 예보만 (aggregateDay)
  assertEquals(d24.destination!.rain, { pop: 80, agreeing: 2, total: 2, rainy: true });
  // 기상청은 10/22까지라 10/23 집 비 소식은 Open-Meteo 3개 계열
  assertEquals(d23.home!.rain!.total, 3);
});

Deno.test("cloud is the daytime mean; snow and precipitation are summed per model and averaged", () => {
  const sapporo = buildTrips(sample(), OPTS).trips[1];
  assertEquals(sapporo.days[0].destination!.cloud, 20);
  assertEquals(sapporo.days[1].destination!.cloud, 95);
  assertEquals(sapporo.days[0].destination!.snowCm, 0);
  // 시간당 0.1cm × 24시간
  assertEquals(sapporo.days[1].destination!.snowCm, 2.4);
  // 강수확률 50% 이상인 날은 시간당 1mm × 24시간
  assertEquals(sapporo.days[0].destination!.precipMm, 0);
  assertEquals(sapporo.days[1].destination!.precipMm, 24);

  // 운량이 없는(옛 캐시) 예보면 null
  const loaded = sample();
  loaded.destinations.set(
    "sapporo",
    loaded.destinations.get("sapporo")!.map((f) => ({
      ...f,
      slots: f.slots.map(({ cloud: _c, snowCm: _s, ...rest }) => rest),
    })),
  );
  const bare = buildTrips(loaded, OPTS).trips[1].days[0].destination!;
  assertEquals([bare.cloud, bare.snowCm], [null, null]);
  // 강수량은 운량·적설 전부터 받던 값이라 그대로 있다
  assertEquals(bare.precipMm, 0);
});

Deno.test("home carries its recent temperatures per Open-Meteo model", () => {
  const { home } = buildTrips(sample(), OPTS);
  assertEquals(home!.name, "집");
  assertEquals(home!.tz, "Asia/Seoul");
  assertEquals(home!.recent.map((h) => h.providers), [["om_ecmwf"], ["om_gfs"], ["om_icon"]]);
  // 10/17 0시부터 오늘 자정까지
  assertEquals(home!.recent[0].start, kst(2026, 10, 17, 0));
  assertEquals(home!.recent[0].temps.length, 4 * 24);
});

Deno.test("a destination behind home keeps its today; home has no rain for its past date", () => {
  const honolulu = place("hnl-id", "호놀룰루", "Pacific/Honolulu");
  const hnl: Array<[string, DaySpec]> = [
    ["2026-10-18", { high: 29, low: 22, pop: 20, cloud: 30 }],
    ["2026-10-19", { high: 29, low: 22, pop: 20, cloud: 30 }],
    ["2026-10-20", { high: 30, low: 23, pop: 60, cloud: 70 }],
  ];
  const loaded: LoadedTrips = {
    ...sample(),
    trips: [trip("hnl", honolulu, "2026-10-19", "2026-10-20")],
    destinations: new Map([["hnl", [forecast("om_ecmwf", "Pacific/Honolulu", hnl)]]]),
  };
  const [day19, day20] = buildTrips(loaded, OPTS).trips[0].days;
  assertEquals(day19.date, "2026-10-19");
  // 호놀룰루는 아직 10/19 11시: 남은 시간의 비 소식
  assertEquals(day19.destination!.rain!.total, 1);
  // 서울의 10/19는 지났다: 기온은 있지만 비 소식은 없다. 하늘은 운량·강수량으로 정한다
  assertEquals(day19.home!.rain, null);
  assert(day19.home!.temps !== null);
  assertEquals([day19.home!.cloud, day19.home!.precipMm], [40, 0]);
  assertEquals(day20.destination!.rain!.pop, 60);
});

Deno.test("without a home the trips still show the destination", () => {
  const res = buildTrips({ ...sample(), home: null, homeForecasts: [] }, OPTS);
  assertEquals(res.home, null);
  const day = res.trips[1].days[0];
  assert(day.destination !== null);
  assertEquals(day.home, null);
});

Deno.test("trips response has no coordinates", () => {
  const json = JSON.stringify(buildTrips(sample(), OPTS));
  assert(!json.includes("lat"));
  assert(!json.includes('lon"'));
});

Deno.test("loading fetches watched destinations once per location and skips the rest", async () => {
  const repo = new MemoryRepo();
  const times = Array.from({ length: 4 }, (_, i) => kst(2026, 10, 20, 6) + i * H);
  const { fn, calls } = routedFetch([[
    /open-meteo/,
    () => openMeteoBody(times, { ecmwf_ifs025: [0, 0, 0, 0] }),
  ]]);
  const deps = { repo, nowMs: () => NOW * 1000, fetchFn: fn };
  const tokyo = { ...place("tokyo-id", "도쿄", "Asia/Tokyo"), lat: 35.68, lon: 139.65 };
  const tokyo2 = { ...tokyo, id: "tokyo2-id", name: "도쿄 또" };
  const home = { ...HOME, lat: 37.57, lon: 126.98 };

  const loaded = await loadTripForecasts(deps, home, [
    trip("a", tokyo, "2026-10-21", "2026-10-22"),
    trip("b", tokyo2, "2026-10-22", "2026-10-23"),
    trip("far", { ...tokyo, id: "far-id", lat: 1, lon: 1 }, "2026-12-01", "2026-12-02"),
  ]);
  // 집 1번 + 도쿄 1번 (먼 여행은 받지 않는다)
  assertEquals(calls.length, 2);
  assertEquals([...loaded.destinations.keys()], ["a", "b"]);
  assertEquals(loaded.homeForecasts.length, 3);

  // 감시 중인 여행이 없으면 아무것도 받지 않는다
  const idle = routedFetch([]);
  const none = await loadTripForecasts({ ...deps, fetchFn: idle.fn }, home, [
    trip("far", tokyo, "2026-12-01", "2026-12-02"),
  ]);
  assertEquals(idle.calls, []);
  assertEquals(none.homeForecasts, []);
});
