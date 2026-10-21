/**
 * Open-Meteo (키 없음, 비상업 무료). 한 번 호출로 ECMWF·GFS·ICON 모델별 값을 받는다.
 * 모델별 precipitation_probability는 각 모델의 앙상블에서 계산된 값이다.
 */
import {
  type FetchFn,
  type HourSlot,
  PROVIDER_FAMILY,
  ProviderError,
  type ProviderForecast,
  type ProviderId,
} from "../forecast_types.ts";

export const OPEN_METEO_MODELS: Record<string, ProviderId> = {
  ecmwf_ifs025: "om_ecmwf",
  ncep_gfs_seamless: "om_gfs",
  dwd_icon_seamless: "om_icon",
};

const HOUR = 3600;

/**
 * 지난 며칠 값도 받는다(기온 비교: 어제~7일 전 같은 시각). 시각은 UTC 날짜 기준이라
 * 서울(+9시간)의 7일 전 자정부터 채우려면 하루 더 필요하다.
 */
export const OPEN_METEO_PAST_DAYS = 8;

/**
 * 앞으로 받을 날 수. 7일 보기(오늘 ~ 6일 뒤)를 채우려면, UTC 날짜 기준이라 서울 0–9시에도
 * 6일 뒤 현지 자정까지 닿도록 하루 더 받는다.
 */
export const OPEN_METEO_FORECAST_DAYS = 8;

export function openMeteoForecastUrl(
  lat: number,
  lon: number,
  days = OPEN_METEO_FORECAST_DAYS,
  pastDays = OPEN_METEO_PAST_DAYS,
): string {
  const params = new URLSearchParams({
    latitude: lat.toFixed(2),
    longitude: lon.toFixed(2),
    hourly: "precipitation_probability,precipitation,temperature_2m",
    models: Object.keys(OPEN_METEO_MODELS).join(","),
    forecast_days: String(days),
    past_days: String(pastDays),
    timeformat: "unixtime",
    timezone: "GMT",
  });
  return `https://api.open-meteo.com/v1/forecast?${params}`;
}

type Hourly = Record<string, Array<number | null>>;

/**
 * 응답 → 모델별 예보.
 * Open-Meteo의 강수확률·강수량은 "직전 1시간" 값이라 시각 T의 값을 [T-1h, T) 슬롯에 넣는다.
 * 기온은 순간값이라 시각 그대로 쓴다.
 */
export function parseOpenMeteo(body: unknown, fetchedAt: number): ProviderForecast[] {
  const hourly = (body as { hourly?: Hourly })?.hourly;
  const times = hourly?.time as number[] | undefined;
  if (!hourly || !times?.length) {
    const reason = (body as { reason?: string })?.reason ?? "hourly 데이터 없음";
    throw new ProviderError("open-meteo", reason);
  }
  const index = new Map(times.map((t, i) => [t, i]));
  const issuedAt = Math.floor(fetchedAt / HOUR) * HOUR;

  return Object.entries(OPEN_METEO_MODELS).map(([model, provider]) => {
    const pop = hourly[`precipitation_probability_${model}`] ?? [];
    const precip = hourly[`precipitation_${model}`] ?? [];
    const temp = hourly[`temperature_2m_${model}`] ?? [];
    const slots: HourSlot[] = [];
    for (const t of times) {
      const end = index.get(t + HOUR);
      if (end === undefined) continue;
      slots.push({
        t,
        pop: round(pop[end]),
        span: 1,
        precipMm: precip[end] ?? null,
        temp: temp[index.get(t)!] ?? null,
      });
    }
    return {
      provider,
      family: PROVIDER_FAMILY[provider],
      issuedAt,
      fetchedAt,
      slots: slots.filter((s) => s.pop !== null || s.temp !== null),
    };
  });
}

function round(v: number | null | undefined): number | null {
  return v === null || v === undefined ? null : Math.round(v);
}

export async function fetchOpenMeteo(opts: {
  lat: number;
  lon: number;
  nowMs: number;
  fetchFn?: FetchFn;
}): Promise<ProviderForecast[]> {
  const res = await (opts.fetchFn ?? fetch)(openMeteoForecastUrl(opts.lat, opts.lon), {
    signal: AbortSignal.timeout(8_000),
  });
  const text = await res.text();
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new ProviderError("open-meteo", `JSON이 아닌 응답(${res.status}): ${text.slice(0, 200)}`);
  }
  if (!res.ok) {
    throw new ProviderError(
      "open-meteo",
      `${res.status} ${(body as { reason?: string })?.reason ?? ""}`,
    );
  }
  return parseOpenMeteo(body, Math.floor(opts.nowMs / 1000));
}
