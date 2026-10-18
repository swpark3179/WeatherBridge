import { latestVilageBase } from "../_shared/kma_time.ts";
import type { FetchFn } from "../_shared/apns.ts";
import { kmaUrl } from "../_shared/providers/kma.ts";
import { OPEN_METEO_MODELS as MODEL_PROVIDERS } from "../_shared/providers/open_meteo.ts";

/** 서울시청 (기상청 격자 60,127) */
export const SEOUL = { lat: 37.5665, lon: 126.978, nx: 60, ny: 127 };

export const OPEN_METEO_MODELS = Object.keys(MODEL_PROVIDERS);

export interface ProbeResult {
  ok: boolean;
  status: number | null;
  ms: number;
  detail: unknown;
}

export function openMeteoUrl(): string {
  const params = new URLSearchParams({
    latitude: String(SEOUL.lat),
    longitude: String(SEOUL.lon),
    hourly: "precipitation_probability",
    models: OPEN_METEO_MODELS.join(","),
    forecast_days: "2",
    timezone: "Asia/Seoul",
  });
  return `https://api.open-meteo.com/v1/forecast?${params}`;
}

export function kmaVilageUrl(serviceKey: string, nowMs: number): string {
  return kmaUrl("getVilageFcst", serviceKey, latestVilageBase(nowMs), SEOUL);
}

/** Open-Meteo 응답에서 모델별 강수확률 열을 요약한다. */
export function summarizeOpenMeteo(body: unknown) {
  const hourly = (body as { hourly?: Record<string, unknown[]> })?.hourly ?? {};
  const time = (hourly.time ?? []) as string[];
  const columns = Object.entries(hourly).filter(([k]) => k.startsWith("precipitation_probability"));
  return {
    hours: time.length,
    firstTime: time[0] ?? null,
    models: Object.fromEntries(columns.map(([k, values]) => [
      k.replace(/^precipitation_probability_?/, "") || "default",
      {
        nonNull: values.filter((v) => v !== null).length,
        first6: values.slice(0, 6),
      },
    ])),
  };
}

/** 기상청 응답에서 POP(강수확률) 항목을 요약한다. 오류 시 resultCode/메시지를 돌려준다. */
export function summarizeKma(body: unknown) {
  const response = (body as { response?: Record<string, unknown> })?.response;
  const header = response?.header as { resultCode?: string; resultMsg?: string } | undefined;
  if (!header || header.resultCode !== "00") {
    return {
      ok: false,
      resultCode: header?.resultCode ?? null,
      resultMsg: header?.resultMsg ?? null,
    };
  }
  const items = ((response?.body as { items?: { item?: KmaItem[] } })?.items?.item) ?? [];
  const pops = items.filter((i) => i.category === "POP");
  return {
    ok: true,
    baseDate: items[0]?.baseDate ?? null,
    baseTime: items[0]?.baseTime ?? null,
    totalItems: items.length,
    popCount: pops.length,
    firstPops: pops.slice(0, 6).map((i) => ({
      at: `${i.fcstDate} ${i.fcstTime}`,
      pop: Number(i.fcstValue),
    })),
  };
}

interface KmaItem {
  baseDate: string;
  baseTime: string;
  category: string;
  fcstDate: string;
  fcstTime: string;
  fcstValue: string;
}

export async function probeJson(
  url: string,
  summarize: (body: unknown) => unknown,
  fetchFn: FetchFn = fetch,
): Promise<ProbeResult> {
  const started = performance.now();
  try {
    const res = await fetchFn(url, { signal: AbortSignal.timeout(8_000) });
    const text = await res.text();
    const ms = Math.round(performance.now() - started);
    let detail: unknown;
    try {
      detail = summarize(JSON.parse(text));
    } catch {
      // data.go.kr은 인증 오류 등을 JSON 요청에도 XML로 돌려준다.
      detail = { nonJson: text.slice(0, 300) };
    }
    const summaryOk = (detail as { ok?: boolean })?.ok;
    return { ok: res.ok && summaryOk !== false, status: res.status, ms, detail };
  } catch (e) {
    return {
      ok: false,
      status: null,
      ms: Math.round(performance.now() - started),
      detail: { error: String(e) },
    };
  }
}
