import { assert, assertEquals } from "@std/assert";
import { aggregate, rainLevel } from "../supabase/functions/_shared/aggregate.ts";
import type {
  HourSlot,
  ProviderForecast,
  ProviderId,
} from "../supabase/functions/_shared/forecast_types.ts";
import { PROVIDER_FAMILY } from "../supabase/functions/_shared/forecast_types.ts";
import { kst } from "./fixtures.ts";

const T0 = kst(2026, 10, 19, 6);
const H = 3600;

function fc(
  provider: ProviderId,
  pops: Array<number | null>,
  opts: { span?: number[]; temp?: number } = {},
): ProviderForecast {
  const slots: HourSlot[] = pops.map((pop, i) => ({
    t: T0 + i * H,
    pop,
    span: opts.span?.[i] ?? 1,
    precipMm: null,
    temp: opts.temp ?? null,
  }));
  return { provider, family: PROVIDER_FAMILY[provider], issuedAt: T0, fetchedAt: T0, slots };
}

const range = (hours: number) => ({ from: T0, to: T0 + hours * H });

Deno.test("levels match WeatherCore RainLevel boundaries", () => {
  assertEquals([0, 19, 20, 39, 40, 59, 60, 100].map(rainLevel), [
    "clear",
    "clear",
    "low",
    "low",
    "moderate",
    "moderate",
    "high",
    "high",
  ]);
});

Deno.test("weights KMA 1.5 against other families", () => {
  const r = aggregate([
    fc("kma_short", [60]),
    fc("om_ecmwf", [20]),
    fc("om_gfs", [10]),
    fc("om_icon", [10]),
  ], range(1));
  // (60*1.5 + 20 + 10 + 10) / 4.5 = 28.9
  assertEquals(r.hours[0].consensus, 29);
  assertEquals(r.hours[0].min, 10);
  assertEquals(r.hours[0].max, 60);
  assertEquals(r.hours[0].total, 4);
  assertEquals(r.hours[0].agreeing, 1);
  assertEquals(r.hours[0].split, true);
  // 종합은 30 미만이지만 기상청 60%라 강조
  assertEquals(r.hours[0].rainy, true);
});

Deno.test("two families at 60%+ trigger highlight even with a low consensus", () => {
  const r = aggregate([fc("om_ecmwf", [70]), fc("om_gfs", [60]), fc("om_icon", [0])], range(1));
  assertEquals(r.hours[0].consensus, 43);
  assert(r.hours[0].rainy);
  const single = aggregate([fc("om_ecmwf", [70]), fc("om_gfs", [0]), fc("om_icon", [0])], range(1));
  assertEquals(single.hours[0].consensus, 23);
  assertEquals(single.hours[0].rainy, false);
});

Deno.test("3-hour block values are left out of hourly consensus", () => {
  const r = aggregate(
    [fc("kma_short", [90, 90], { span: [1, 3] }), fc("om_ecmwf", [10, 10])],
    range(2),
  );
  assertEquals(r.hours[0].total, 2);
  assertEquals(r.hours[1].total, 1);
  assertEquals(r.hours[1].consensus, 10);
  assert(r.hours[1].bandChange);
  assert(!r.hours[0].bandChange);
});

Deno.test("hours without data stay null and do not break windows", () => {
  const r = aggregate([fc("om_ecmwf", [50, null, 50])], range(3));
  assertEquals(r.hours.map((h) => h.consensus), [50, null, 50]);
  assertEquals(r.windows.length, 2);
});

Deno.test("consecutive rainy hours merge into windows with their peak", () => {
  const r = aggregate(
    [fc("om_ecmwf", [0, 30, 70, 40, 0, 35]), fc("om_gfs", [0, 30, 50, 40, 0, 35])],
    { ...range(6), threshold: 30 },
  );
  assertEquals(r.windows.map((w) => [(w.start - T0) / H, (w.end - T0) / H, w.maxPop]), [
    [1, 4, 60],
    [5, 6, 35],
  ]);
  assertEquals(r.windows[0].agreeing, 2);
  assertEquals(r.maxPop, 60);
  assert(r.highlight);
});

Deno.test("no rain means no highlight", () => {
  const r = aggregate([fc("om_ecmwf", [0, 10, 20])], range(3));
  assertEquals(r.windows, []);
  assertEquals(r.highlight, false);
  assertEquals(r.maxPop, 20);
});

Deno.test("temperature prefers KMA, then ECMWF", () => {
  const r = aggregate(
    [fc("om_ecmwf", [0], { temp: 9 }), fc("kma_short", [0], { temp: 12 })],
    range(1),
  );
  assertEquals(r.hours[0].temp, 12);
  const r2 = aggregate(
    [fc("om_gfs", [0], { temp: 7 }), fc("om_ecmwf", [0], { temp: 9 })],
    range(1),
  );
  assertEquals(r2.hours[0].temp, 9);
});

Deno.test("slots outside the range are ignored", () => {
  const r = aggregate([fc("om_ecmwf", [90, 90, 90])], { from: T0 + H, to: T0 + 2 * H });
  assertEquals(r.hours.length, 1);
  assertEquals(r.hours[0].t, T0 + H);
});
