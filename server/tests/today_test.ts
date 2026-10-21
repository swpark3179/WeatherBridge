import { assert, assertEquals } from "@std/assert";
import type { Place } from "../supabase/functions/_shared/db.ts";
import { MemoryRepo } from "../supabase/functions/_shared/db.ts";
import type { ProviderForecast, ProviderId } from "../supabase/functions/_shared/forecast_types.ts";
import { PROVIDER_FAMILY } from "../supabase/functions/_shared/forecast_types.ts";
import {
  buildToday,
  dailyRain,
  type LoadedPlace,
  loadForecasts,
  recentTemps,
  tempHistory,
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

/** 어제 같은 시각(06시부터)의 기온을 앞에 붙인다. Open-Meteo는 past_days로 지난 값도 준다. */
function withYesterday(f: ProviderForecast, temps: number[]): ProviderForecast {
  const past = temps.map((temp, i) => ({
    t: T0 - 24 * H + i * H,
    pop: null,
    span: 1,
    precipMm: null,
    temp,
  }));
  return { ...f, slots: [...past, ...f.slots] };
}

/** 뒤 날짜 강수확률을 붙인다: [10/21부터 며칠째, 시, 강수확률] */
function withLater(f: ProviderForecast, values: Array<[number, number, number]>): ProviderForecast {
  const later = values.map(([day, hour, pop]) => ({
    t: kst(2026, 10, 21 + day, hour),
    pop,
    span: 1,
    precipMm: null,
    temp: null,
  }));
  return { ...f, slots: [...f.slots, ...later] };
}

/**
 * 계약 샘플용 입력: 집은 08–10시 비, 회사는 비 소식 없음, 06시부터 4시간.
 * 집은 ECMWF에 어제 06–09시 기온도 있어 기온 비교가 된다(오늘이 2–3° 낮다).
 * 집은 10/22까지 값이 있어 7일 보기가 3일치다. 기상청은 10/22 정오에 끝나 그 날에서 빠진다.
 * 회사는 오늘 10시에 예보가 끝나 날짜별 값이 없다.
 */
function sample(): LoadedPlace[] {
  return [
    {
      place: place("home", "집"),
      forecasts: [
        withLater(fc("kma_short", [10, 20, 60, 70], [15, 16, 17, 17]), [
          [0, 12, 30],
          [0, 23, 0],
          [1, 11, 80],
        ]),
        withYesterday(
          withLater(fc("om_ecmwf", [5, 30, 80, 90], [14.6, 15.2, 16.1, 16.4]), [
            [0, 15, 20],
            [1, 14, 40],
            [1, 23, 0],
          ]),
          [17.1, 18.0, 19.2, 19.9],
        ),
        withLater(fc("om_gfs", [0, 10, 40, 60]), [[0, 9, 10], [1, 16, 70], [1, 23, 0]]),
        withLater(fc("om_icon", [0, 0, 20, 50]), [[0, 18, 0], [1, 13, 20], [1, 23, 0]]),
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

/** 시각 → 기온 함수로 [from, to) 시간별 슬롯을 만든다 */
function tempSeries(
  provider: ProviderId,
  from: number,
  to: number,
  temp: (t: number) => number | null,
): ProviderForecast {
  const slots = [];
  for (let t = from; t < to; t += H) slots.push({ t, pop: 0, span: 1, precipMm: 0, temp: temp(t) });
  return { provider, family: PROVIDER_FAMILY[provider], issuedAt: T0, fetchedAt: T0, slots };
}

Deno.test("temperature history covers seven local days before today until tonight", () => {
  // 서울 기준 10/13 00시 ~ 10/21 00시. 범위 밖 값은 잘라 낸다.
  const wide = [kst(2026, 10, 11, 0), kst(2026, 10, 23, 0)] as const;
  const history = tempHistory([
    tempSeries("om_ecmwf", ...wide, (t) => 10 + ((t - T0) / H) * 0.1),
    tempSeries("om_icon", ...wide, (t) => 12 + ((t - T0) / H) * 0.1),
  ], { nowSec: NOW, tz: "Asia/Seoul" });

  assert(history);
  assertEquals(history.providers, ["om_ecmwf", "om_icon"]);
  assertEquals(history.start, kst(2026, 10, 13, 0));
  assertEquals(history.temps.length, 8 * 24);
  // 오늘 06시: (10 + 12) / 2, 어제 06시는 24시간 전이라 2.4° 낮다
  const at = (t: number) => history.temps[(t - history.start) / H];
  assertEquals(at(T0), 11);
  assertEquals(at(T0 - 24 * H), 8.6);
  assertEquals(at(kst(2026, 10, 20, 23)), 12.7);
});

Deno.test("temperature history keeps one source mix: no forecast-only sources or partial hours", () => {
  const from = kst(2026, 10, 19, 0);
  const to = kst(2026, 10, 21, 0);
  const history = tempHistory([
    // 기상청은 지난 시간이 없어서 쓰지 않는다
    tempSeries("kma_short", T0, to, () => 30),
    tempSeries("om_ecmwf", from, to, () => 10),
    // ICON은 어제 12시 값이 없다 → 그 시간은 ECMWF만의 평균 대신 비운다
    tempSeries("om_icon", from, to, (t) => (t === kst(2026, 10, 19, 12) ? null : 12)),
    // GFS는 오늘 값만 있어 날짜마다 평균 구성이 달라지므로 뺀다
    tempSeries("om_gfs", T0, to, () => 20),
  ], { nowSec: NOW, tz: "Asia/Seoul" });

  assert(history);
  assertEquals(history.providers, ["om_ecmwf", "om_icon"]);
  // 앞뒤 빈 시간은 잘라 낸다: 어제 0시부터
  assertEquals(history.start, from);
  assertEquals(history.temps.length, 48);
  assertEquals(history.temps[12], null);
  assertEquals(history.temps.filter((v) => v !== null && v !== 11), []);
});

Deno.test("temperature history is null without Open-Meteo temperatures", () => {
  assertEquals(
    tempHistory([tempSeries("kma_short", T0, T0 + 4 * H, () => 15)], {
      nowSec: NOW,
      tz: "Asia/Seoul",
    }),
    null,
  );
  assertEquals(
    tempHistory([tempSeries("om_ecmwf", T0, T0 + 4 * H, () => null)], {
      nowSec: NOW,
      tz: "Asia/Seoul",
    }),
    null,
  );
});

Deno.test("today response carries the temperature history per place", () => {
  const r = buildToday(sample(), { nowSec: NOW, tz: "Asia/Seoul", threshold: 30, horizonHours: 4 });
  const home = r.places[0].tempHistory;
  assert(home);
  // 집은 ECMWF만 기온이 있다. 어제 06시부터 오늘 09시까지(중간 20시간은 비어 있음).
  assertEquals(home.providers, ["om_ecmwf"]);
  assertEquals(home.start, T0 - 24 * H);
  assertEquals(home.temps.length, 28);
  assertEquals(home.temps.slice(0, 4), [17.1, 18, 19.2, 19.9]);
  assertEquals(home.temps.slice(24), [14.6, 15.2, 16.1, 16.4]);
  // 회사는 Open-Meteo 기온이 없다
  assertEquals(r.places[1].tempHistory, null);
  // 7일 보기 기준: 지난 기온이 있는 모델(ECMWF)만, 오늘은 빼고
  assertEquals(r.places[0].recentTemps, [
    { providers: ["om_ecmwf"], start: T0 - 24 * H, temps: [17.1, 18, 19.2, 19.9] },
  ]);
  assertEquals(r.places[1].recentTemps, []);
});

/** 모델마다 조금씩 다른 치우침: 모델끼리 섞지 않아야 앱이 같은 모델로 기준을 만들 수 있다 */
const BIAS: Partial<Record<ProviderId, number>> = { om_ecmwf: 0, om_gfs: 1, om_icon: -0.6 };
const WIDE = [kst(2026, 10, 11, 0), kst(2026, 10, 30, 0)] as const;
const hourly = (t: number) => 10 + ((t - T0) / H) * 0.1;

Deno.test("recent temperatures carry the last three local days per Open-Meteo model", () => {
  const recent = recentTemps([
    tempSeries("kma_short", ...WIDE, () => 30),
    ...(["om_ecmwf", "om_gfs", "om_icon"] as const).map((p) =>
      tempSeries(p, ...WIDE, (t) => Math.round((hourly(t) + BIAS[p]!) * 10) / 10)
    ),
  ], { nowSec: NOW, tz: "Asia/Seoul" });

  // 기상청은 지난 시간이 없어 빠지고, 모델끼리 평균하지 않는다
  assertEquals(recent.map((h) => h.providers), [["om_ecmwf"], ["om_gfs"], ["om_icon"]]);
  for (const h of recent) {
    // 3일 전(10/17) 0시부터 어제 자정까지: 오늘은 들어가지 않는다
    assertEquals(h.start, kst(2026, 10, 17, 0));
    assertEquals(h.temps.length, 3 * 24);
  }
  const at = (i: number, t: number) => recent[i].temps[(t - recent[i].start) / H];
  const yesterdayNoon = kst(2026, 10, 19, 12);
  assertEquals(at(0, yesterdayNoon), 8.2);
  assertEquals(at(1, yesterdayNoon), 9.2);
  assertEquals(at(2, yesterdayNoon), 7.6);
});

Deno.test("recent temperatures leave out models without past values", () => {
  const recent = recentTemps([
    tempSeries("om_ecmwf", ...WIDE, () => 10),
    // GFS는 오늘 값만 있다
    tempSeries("om_gfs", kst(2026, 10, 20, 0), WIDE[1], () => 11),
  ], { nowSec: NOW, tz: "Asia/Seoul" });
  assertEquals(recent.map((h) => h.providers), [["om_ecmwf"]]);
  assertEquals(
    recentTemps([tempSeries("kma_short", ...WIDE, () => 15)], { nowSec: NOW, tz: "Asia/Seoul" }),
    [],
  );
});

Deno.test("daily temps use the models that reach each day's end", () => {
  const days = dailyRain([
    tempSeries("om_ecmwf", ...WIDE, (t) => hourly(t)),
    tempSeries("om_gfs", ...WIDE, (t) => hourly(t) + 1),
    // ICON은 10/25(5일째) 06시에 끝난다 → 그 날부터는 ECMWF·GFS만
    tempSeries("om_icon", WIDE[0], kst(2026, 10, 25, 7), (t) => hourly(t) - 0.6),
  ], { nowSec: NOW, tz: "Asia/Seoul", threshold: 30 });

  assertEquals(days.length, 7);
  assertEquals(
    days.map((d) => d.temps?.providers),
    [
      ...Array(5).fill(["om_ecmwf", "om_gfs", "om_icon"]),
      ["om_ecmwf", "om_gfs"],
      ["om_ecmwf", "om_gfs"],
    ],
  );
  // 오늘도 0시부터 하루 전체 (지난 시간은 모델이 남긴 값)
  const today = days[0].temps!;
  assertEquals(today.start, kst(2026, 10, 20, 0));
  assertEquals(today.temps.length, 24);
  // 오늘 06시: (10 + 11 + 9.4) / 3
  assertEquals(today.temps[6], 10.1);
  assertEquals(days[6].temps!.start, kst(2026, 10, 26, 0));
});

Deno.test("a day no model's temperatures reach keeps its rain without temps", () => {
  const days = dailyRain([
    tempSeries("om_ecmwf", ...WIDE, (t) => (t < kst(2026, 10, 22, 12) ? 10 : null)),
  ], { nowSec: NOW, tz: "Asia/Seoul", threshold: 30 });
  assertEquals(days.length, 7);
  assertEquals(days.map((d) => d.temps !== null), [true, true, false, false, false, false, false]);
  assertEquals(days[2].pop, 0);
});

Deno.test("daily temps follow local days across a DST change", () => {
  // 뉴욕 10/30 10시(EDT). 11/1에 서머타임이 끝나 그 날은 25시간이다.
  const now = Date.UTC(2026, 9, 30, 14) / 1000;
  const series = tempSeries("om_ecmwf", now - 3 * 24 * H, now + 9 * 24 * H, () => 12);
  const days = dailyRain([series], { nowSec: now, tz: "America/New_York", threshold: 30 });
  assertEquals(days[2].temps?.start, Date.UTC(2026, 10, 1, 4) / 1000);
  assertEquals(days[2].temps?.temps.length, 25);
  assertEquals(days[3].temps?.temps.length, 24);
});

Deno.test("today response carries the daily rain per place", () => {
  const r = buildToday(sample(), { nowSec: NOW, tz: "Asia/Seoul", threshold: 30, horizonHours: 4 });
  assertEquals(r.places[0].days, [
    // 오늘: 계열 최고 70·90·60·50 → (70×1.5 + 90 + 60 + 50) / 4.5
    // 기온은 하루 끝까지 닿는 모델이 없어 비어 있다 (ECMWF 기온은 오늘 09시까지)
    { date: kst(2026, 10, 20, 0), pop: 68, agreeing: 4, total: 4, rainy: true, temps: null },
    // 내일: 30·20·10·0 → 17%, 기준 이상은 기상청 하나
    { date: kst(2026, 10, 21, 0), pop: 17, agreeing: 1, total: 4, rainy: false, temps: null },
    // 모레: 기상청(정오에 끝남)의 80%는 빼고 40·70·20
    { date: kst(2026, 10, 22, 0), pop: 43, agreeing: 2, total: 3, rainy: true, temps: null },
  ]);
  assertEquals(r.places[1].days, []);
  // 날짜별 값은 시간별 범위(horizonHours)와 따로 계산한다
  assertEquals(r.places[0].hours.length, 4);
});

/** 시각 → 강수확률 함수로 [from, to) 시간별 슬롯을 만든다 */
function popSeries(
  provider: ProviderId,
  from: number,
  to: number,
  pop: (t: number) => number,
): ProviderForecast {
  const slots = [];
  for (let t = from; t < to; t += H) {
    slots.push({ t, pop: pop(t), span: 1, precipMm: 0, temp: null });
  }
  return { provider, family: PROVIDER_FAMILY[provider], issuedAt: T0, fetchedAt: T0, slots };
}

Deno.test("daily rain covers seven local days, today from the current hour", () => {
  // 날마다 정오에 5%, 15% … 65%. 오늘 03시(이미 지난 시간)의 90%는 세지 않는다.
  const noon = (i: number) => kst(2026, 10, 20 + i, 12);
  const series = popSeries("om_ecmwf", kst(2026, 10, 20, 0), kst(2026, 10, 29, 0), (t) => {
    if (t === kst(2026, 10, 20, 3)) return 90;
    const i = [...Array(9).keys()].find((i) => noon(i) === t);
    return i === undefined ? 0 : i * 10 + 5;
  });
  const days = dailyRain([series], { nowSec: NOW, tz: "Asia/Seoul", threshold: 30 });
  assertEquals(days.map((d) => d.date), [...Array(7).keys()].map((i) => kst(2026, 10, 20 + i, 0)));
  assertEquals(days.map((d) => d.pop), [5, 15, 25, 35, 45, 55, 65]);
  assertEquals(days.map((d) => d.rainy), [false, false, false, true, true, true, true]);
});

Deno.test("daily rain splits days at local midnight across a DST change", () => {
  // 뉴욕 10/30 10시(EDT). 11/1에 서머타임이 끝나 그 날은 25시간이다.
  const now = Date.UTC(2026, 9, 30, 14) / 1000;
  const series = popSeries("om_gfs", now - 10 * H, now + 9 * 24 * H, () => 10);
  const days = dailyRain([series], { nowSec: now, tz: "America/New_York", threshold: 30 });
  assertEquals(days.length, 7);
  assertEquals(days[0].date, Date.UTC(2026, 9, 30, 4) / 1000);
  assertEquals(days[2].date, Date.UTC(2026, 10, 1, 4) / 1000);
  assertEquals(days[3].date, Date.UTC(2026, 10, 2, 5) / 1000);
});
