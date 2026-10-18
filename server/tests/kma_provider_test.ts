import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { ProviderError } from "../supabase/functions/_shared/forecast_types.ts";
import {
  fetchKmaObservation,
  fetchKmaShort,
  parseKmaPage,
  parsePcp,
} from "../supabase/functions/_shared/providers/kma.ts";
import { kmaNcstBody, kmaVilageBody, kst, routedFetch } from "./fixtures.ts";

const SEOUL = { nx: 60, ny: 127 };

Deno.test("parses PCP strings to mm", () => {
  assertEquals(parsePcp("강수없음"), 0);
  assertEquals(parsePcp("1mm 미만"), 0.5);
  assertEquals(parsePcp("1.0mm 미만"), 0.5);
  assertEquals(parsePcp("6.2mm"), 6.2);
  assertEquals(parsePcp("30.0~50.0mm"), 40);
  assertEquals(parsePcp("50.0mm 이상"), 50);
  assertEquals(parsePcp("약한 비"), null);
});

Deno.test("short forecast becomes hourly slots in UTC with 3h spans in the extended range", async () => {
  const issued = kst(2026, 10, 19, 5);
  const t0 = kst(2026, 10, 19, 6);
  const { fn, calls } = routedFetch([[
    /getVilageFcst/,
    () =>
      kmaVilageBody(issued, [
        { t: t0, pop: 10, tmp: 12 },
        { t: t0 + 3600, pop: 60, pcp: "1.0mm", tmp: 13 },
        { t: t0 + 7200, pop: 30 },
        // 연장구간: 3시간 간격
        { t: t0 + 5 * 3600, pop: 40 },
        { t: t0 + 8 * 3600, pop: 20 },
      ]),
  ]]);

  const f = await fetchKmaShort({
    serviceKey: "k",
    grid: SEOUL,
    nowMs: kst(2026, 10, 19, 5, 20) * 1000,
    fetchFn: fn,
  });

  assertEquals(f.provider, "kma_short");
  assertEquals(f.family, "kma");
  assertEquals(f.issuedAt, issued);
  assertEquals(f.slots.map((s) => [s.t - t0, s.pop, s.span]), [
    [0, 10, 1],
    [3600, 60, 1],
    [7200, 30, 1],
    [5 * 3600, 40, 3],
    [8 * 3600, 20, 3],
  ]);
  assertEquals(f.slots[1].precipMm, 1);
  assertEquals(f.slots[0].temp, 12);
  const url = new URL(calls[0]);
  assertEquals(url.searchParams.get("base_time"), "0500");
  assertEquals(url.searchParams.get("nx"), "60");
});

Deno.test("reads further pages until totalCount", async () => {
  const issued = kst(2026, 10, 19, 5);
  const page = (pop: number, t: number) => {
    const body = JSON.parse(kmaVilageBody(issued, [{ t, pop }]));
    body.response.body.totalCount = 8; // 슬롯당 4항목 × 2페이지
    return JSON.stringify(body);
  };
  const t0 = kst(2026, 10, 19, 6);
  const { fn, calls } = routedFetch([
    [/pageNo=1&/, () => page(10, t0)],
    [/pageNo=2&/, () => page(20, t0 + 3600)],
  ]);
  const f = await fetchKmaShort({
    serviceKey: "k",
    grid: SEOUL,
    nowMs: issued * 1000 + 30 * 60_000,
    fetchFn: fn,
  });
  assertEquals(calls.length, 2);
  assertEquals(f.slots.map((s) => s.pop), [10, 20]);
});

Deno.test("error responses raise ProviderError", () => {
  assertThrows(
    () => parseKmaPage('{"response":{"header":{"resultCode":"03","resultMsg":"NO_DATA"}}}'),
    ProviderError,
    "NO_DATA",
  );
  assertThrows(
    () => parseKmaPage("<OpenAPI_ServiceResponse>SERVICE_KEY_IS_NOT_REGISTERED_ERROR"),
    ProviderError,
    "SERVICE_KEY_IS_NOT_REGISTERED_ERROR",
  );
});

Deno.test("empty forecast is an error, not an empty result", async () => {
  const { fn } = routedFetch([[/getVilageFcst/, () => kmaVilageBody(kst(2026, 10, 19, 5), [])]]);
  await assertRejects(
    () => fetchKmaShort({ serviceKey: "k", grid: SEOUL, nowMs: Date.now(), fetchFn: fn }),
    ProviderError,
  );
});

Deno.test("observation keeps RN1/PTY/T1H and drops missing values", async () => {
  const obsTime = kst(2026, 10, 19, 6);
  const { fn, calls } = routedFetch([[
    /getUltraSrtNcst/,
    () => kmaNcstBody(obsTime, { RN1: "1.5", PTY: "1", T1H: "-998.9", REH: "80" }),
  ]]);
  const obs = await fetchKmaObservation({
    serviceKey: "k",
    grid: SEOUL,
    nowMs: kst(2026, 10, 19, 7, 20) * 1000,
    fetchFn: fn,
  });
  assertEquals(obs, { locKey: "kma:60:127", obsTime, rn1: 1.5, pty: 1, t1h: null });
  assertEquals(new URL(calls[0]).searchParams.get("base_time"), "0600");
});
