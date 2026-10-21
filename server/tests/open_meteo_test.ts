import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { ProviderError } from "../supabase/functions/_shared/forecast_types.ts";
import {
  fetchOpenMeteo,
  openMeteoForecastUrl,
  parseOpenMeteo,
} from "../supabase/functions/_shared/providers/open_meteo.ts";
import { kst, openMeteoBody, routedFetch } from "./fixtures.ts";

const T0 = kst(2026, 10, 19, 0);
const times = [T0, T0 + 3600, T0 + 7200, T0 + 10800];

Deno.test("url requests three models in unix time, rounded to ~1km", () => {
  const url = new URL(openMeteoForecastUrl(37.56651, 126.97801));
  assertEquals(url.searchParams.get("latitude"), "37.57");
  assertEquals(url.searchParams.get("longitude"), "126.98");
  assertEquals(url.searchParams.get("models"), "ecmwf_ifs025,ncep_gfs_seamless,dwd_icon_seamless");
  assertEquals(url.searchParams.get("timeformat"), "unixtime");
  // 기온 비교용 지난 값: 서울 7일 전 자정부터 채우려면 UTC로 8일
  assertEquals(url.searchParams.get("past_days"), "8");
  // 여행 화면: 16일 뒤까지 (7일 보기는 8일이면 충분)
  assertEquals(url.searchParams.get("forecast_days"), "16");
  assertEquals(
    url.searchParams.get("hourly"),
    "precipitation_probability,precipitation,temperature_2m,cloud_cover,snowfall",
  );
});

Deno.test("preceding-hour values move to the slot that starts an hour earlier", () => {
  const body = JSON.parse(
    openMeteoBody(
      times,
      {
        ecmwf_ifs025: [5, 10, 49, 70],
        ncep_gfs_seamless: [0, 0, 4, 11],
        dwd_icon_seamless: [null, null, null, null],
      },
      {
        ecmwf_ifs025: [10, 11, 12, 13],
        ncep_gfs_seamless: [9, 9, 9, 9],
        dwd_icon_seamless: [8, 8, 8, 8],
      },
    ),
  );
  const [ecmwf, gfs, icon] = parseOpenMeteo(body, T0 + 600);

  assertEquals(ecmwf.provider, "om_ecmwf");
  assertEquals(ecmwf.family, "ecmwf");
  assertEquals(ecmwf.issuedAt, T0);
  // 01시 값(10%)은 00–01시 슬롯
  assertEquals(ecmwf.slots.map((s) => [s.t - T0, s.pop, s.temp]), [
    [0, 10, 10],
    [3600, 49, 11],
    [7200, 70, 12],
  ]);
  assertEquals(gfs.family, "ncep");
  assertEquals(gfs.slots.map((s) => s.pop), [0, 4, 11]);
  // 확률이 없어도 기온이 있으면 슬롯은 남는다
  assertEquals(icon.family, "dwd");
  assertEquals(icon.slots.map((s) => s.pop), [null, null, null]);
});

Deno.test("cloud cover stays at its hour; snowfall moves like precipitation", () => {
  const body = JSON.parse(
    openMeteoBody(
      times,
      { ecmwf_ifs025: [0, 60, 70, 80], ncep_gfs_seamless: [0, 0, 0, 0] },
      undefined,
      {
        cloud: { ecmwf_ifs025: [10, 55.4, 90, 100] },
        snow: { ecmwf_ifs025: [0, 0.7, 1.4, 0] },
      },
    ),
  );
  const [ecmwf, gfs] = parseOpenMeteo(body, T0);
  assertEquals(ecmwf.slots.map((s) => [s.t - T0, s.cloud, s.snowCm]), [
    [0, 10, 0.7],
    [3600, 55, 1.4],
    [7200, 90, 0],
  ]);
  // 운량·적설이 없는 응답이면 null
  assertEquals(gfs.slots.map((s) => [s.cloud, s.snowCm]), [[null, null], [null, null], [
    null,
    null,
  ]]);
});

Deno.test("error bodies raise ProviderError", async () => {
  assertThrows(
    () => parseOpenMeteo({ error: true, reason: "Too many requests" }, 0),
    ProviderError,
    "Too many",
  );
  const { fn } = routedFetch([[
    /open-meteo/,
    () => new Response(JSON.stringify({ error: true, reason: "Invalid model" }), { status: 400 }),
  ]]);
  await assertRejects(
    () => fetchOpenMeteo({ lat: 37.57, lon: 126.98, nowMs: 0, fetchFn: fn }),
    ProviderError,
    "Invalid model",
  );
});
