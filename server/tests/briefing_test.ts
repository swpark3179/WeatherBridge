import { assert, assertEquals } from "@std/assert";
import { aggregate } from "../supabase/functions/_shared/aggregate.ts";
import {
  buildBriefing,
  localHour,
  restOfLocalDay,
} from "../supabase/functions/_shared/briefing.ts";
import type { ProviderForecast, ProviderId } from "../supabase/functions/_shared/forecast_types.ts";
import { PROVIDER_FAMILY } from "../supabase/functions/_shared/forecast_types.ts";
import { kst } from "./fixtures.ts";

const TZ = "Asia/Seoul";
const H = 3600;

/** fromHour(KST)부터 시간별 값 */
function fc(provider: ProviderId, fromSec: number, pops: number[], temp = 12): ProviderForecast {
  return {
    provider,
    family: PROVIDER_FAMILY[provider],
    issuedAt: fromSec,
    fetchedAt: fromSec,
    slots: pops.map((pop, i) => ({ t: fromSec + i * H, pop, span: 1, precipMm: null, temp })),
  };
}

Deno.test("rest of day runs from the current hour to local midnight", () => {
  const now = kst(2026, 10, 19, 7, 25);
  const { from, to } = restOfLocalDay(now, TZ);
  assertEquals(from, kst(2026, 10, 19, 7));
  assertEquals(to, kst(2026, 10, 20, 0));
  assertEquals(localHour(from, TZ), 7);
});

Deno.test("headline names the rainy place, window and peak", () => {
  const now = kst(2026, 10, 19, 7, 5);
  const range = restOfLocalDay(now, TZ);
  const hours = (to: number) => (to - range.from) / H; // 17시간
  const home = new Array(hours(range.to)).fill(10);
  const office = new Array(hours(range.to)).fill(0);
  office[8] = 40; // 15시
  office[9] = 70; // 16시
  office[10] = 50; // 17시
  const b = buildBriefing({
    nowSec: now,
    tz: TZ,
    places: [
      { name: "집", aggregate: aggregate([fc("om_ecmwf", range.from, home)], range) },
      { name: "회사", aggregate: aggregate([fc("om_ecmwf", range.from, office, 15)], range) },
    ],
  });

  assertEquals(b.state.headline, "☔ 회사 15–18시 최대 70%");
  assert(b.state.highlight);
  assertEquals(b.firstHour, 7);
  assertEquals(b.state.places.map((p) => [p.name, p.temp, p.maxPop, p.rainWindow]), [
    ["집", 12, 10, null],
    ["회사", 15, 70, "15–18시"],
  ]);
  assertEquals(b.state.places[0].pops.length, 17);
  assertEquals(b.state.updatedAt, now);
  assertEquals(b.summary, "집 비 소식 없음(최대 10%) / 회사 ☔ 15–18시 최대 70%");
});

Deno.test("dry day headline and single-hour window label", () => {
  const now = kst(2026, 10, 19, 20, 0);
  const range = restOfLocalDay(now, TZ);
  const dry = buildBriefing({
    nowSec: now,
    tz: TZ,
    places: [{
      name: "집",
      aggregate: aggregate([fc("om_ecmwf", range.from, [0, 10, 0, 0])], range),
    }],
  });
  assertEquals(dry.state.headline, "오늘 비 소식 없음 (최대 10%)");
  assertEquals(dry.state.highlight, false);

  const shower = buildBriefing({
    nowSec: now,
    tz: TZ,
    places: [{
      name: "집",
      aggregate: aggregate([fc("om_ecmwf", range.from, [0, 0, 0, 45])], range),
    }],
  });
  assertEquals(shower.state.headline, "☔ 집 23시 최대 45%");
});

Deno.test("both places rainy are listed, wettest first", () => {
  const now = kst(2026, 10, 19, 21, 0);
  const range = restOfLocalDay(now, TZ);
  const b = buildBriefing({
    nowSec: now,
    tz: TZ,
    places: [
      { name: "집", aggregate: aggregate([fc("om_ecmwf", range.from, [40, 40, 0])], range) },
      { name: "회사", aggregate: aggregate([fc("om_ecmwf", range.from, [0, 0, 80])], range) },
    ],
  });
  assertEquals(b.state.headline, "☔ 회사 23시 최대 80% · 집 21–23시 최대 40%");
});
