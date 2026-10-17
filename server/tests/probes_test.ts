import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import {
  kmaVilageUrl,
  openMeteoUrl,
  probeJson,
  summarizeKma,
  summarizeOpenMeteo,
} from "../supabase/functions/spike-reach/probes.ts";

Deno.test("open-meteo url requests per-model precipitation probability", () => {
  const url = new URL(openMeteoUrl());
  assertEquals(url.searchParams.get("hourly"), "precipitation_probability");
  assertEquals(url.searchParams.get("models"), "ecmwf_ifs025,ncep_gfs_seamless,dwd_icon_seamless");
  assertEquals(url.searchParams.get("timezone"), "Asia/Seoul");
});

Deno.test("summarizes open-meteo model columns", () => {
  const summary = summarizeOpenMeteo({
    hourly: {
      time: ["2026-10-19T00:00", "2026-10-19T01:00"],
      precipitation_probability_ecmwf_ifs025: [10, 20],
      precipitation_probability_ncep_gfs_seamless: [null, 30],
    },
  });
  assertEquals(summary.hours, 2);
  assertEquals(summary.models.ecmwf_ifs025, { nonNull: 2, first6: [10, 20] });
  assertEquals(summary.models.ncep_gfs_seamless.nonNull, 1);
});

Deno.test("kma url uses grid and computed base time", () => {
  const url = new URL(kmaVilageUrl("a+b/c==", Date.UTC(2026, 9, 18, 22, 0))); // 07:00 KST
  assertEquals(url.searchParams.get("serviceKey"), "a+b/c==");
  assertStringIncludes(url.search, "serviceKey=a%2Bb%2Fc%3D%3D");
  assertEquals(url.searchParams.get("base_date"), "20261019");
  assertEquals(url.searchParams.get("base_time"), "0500");
  assertEquals(url.searchParams.get("nx"), "60");
  assertEquals(url.searchParams.get("ny"), "127");
});

Deno.test("summarizes kma POP items", () => {
  const item = (category: string, fcstTime: string, fcstValue: string) => ({
    baseDate: "20261019",
    baseTime: "0500",
    category,
    fcstDate: "20261019",
    fcstTime,
    fcstValue,
  });
  const summary = summarizeKma({
    response: {
      header: { resultCode: "00", resultMsg: "NORMAL_SERVICE" },
      body: { items: { item: [item("TMP", "0600", "12"), item("POP", "0600", "30")] } },
    },
  });
  assertEquals(summary, {
    ok: true,
    baseDate: "20261019",
    baseTime: "0500",
    totalItems: 2,
    popCount: 1,
    firstPops: [{ at: "20261019 0600", pop: 30 }],
  });
});

Deno.test("reports kma error codes", () => {
  const summary = summarizeKma({
    response: { header: { resultCode: "03", resultMsg: "NO_DATA" } },
  });
  assertEquals(summary, { ok: false, resultCode: "03", resultMsg: "NO_DATA" });
});

Deno.test("probeJson handles XML error bodies and network failures", async () => {
  const xml = await probeJson(
    "https://example.test",
    summarizeKma,
    () =>
      Promise.resolve(new Response("<OpenAPI_ServiceResponse>SERVICE_KEY_IS_NOT_REGISTERED_ERROR")),
  );
  assertEquals(xml.status, 200);
  assertStringIncludes(JSON.stringify(xml.detail), "SERVICE_KEY_IS_NOT_REGISTERED_ERROR");

  const failed = await probeJson(
    "https://example.test",
    summarizeKma,
    () => Promise.reject(new Error("boom")),
  );
  assertEquals(failed.ok, false);
  assertEquals(failed.status, null);

  const kmaError = await probeJson(
    "https://example.test",
    summarizeKma,
    () => Promise.resolve(Response.json({ response: { header: { resultCode: "30" } } })),
  );
  assert(!kmaError.ok);
});
