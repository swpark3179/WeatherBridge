/**
 * 하루 날씨와 시간별 기온 평균. 앱 "날씨"·"기온" 탭(today.ts)과 "여행"(trips.ts)이 함께 쓴다.
 * 기온은 지난 값도 주는 Open-Meteo 모델끼리만 평균하고, 쓴 모델을 함께 싣는다(D21·D24).
 */
import { aggregateDay } from "./aggregate.ts";
import type { ProviderForecast, ProviderId } from "./forecast_types.ts";
import { OPEN_METEO_MODELS } from "./providers/open_meteo.ts";
import { addDays, type LocalDate, parseLocalDate, zonedEpoch } from "./schedule.ts";

/** 지난 값도 주는 소스 (기온 비교·여행 기온은 이 모델들끼리만 평균한다) */
export const OPEN_METEO_PROVIDERS: ReadonlySet<ProviderId> = new Set(
  Object.values(OPEN_METEO_MODELS),
);

/** 값이 가장 많은 소스의 이 비율보다 적게 가진 소스는 기온 평균에서 뺀다 */
const TEMP_HISTORY_MIN_COVERAGE = 0.9;

/**
 * 지난 며칠과 오늘의 시간별 기온. 앱이 오늘 기온을 어제·최근 며칠의 같은 시각과 비교한다.
 * 모든 시간이 같은 소스 묶음의 평균이라, 소스마다 다른 치우침(격자·고도)이 날짜 간 차이에서 빠진다.
 */
export interface TempHistory {
  /** 평균에 쓴 소스 */
  providers: ProviderId[];
  /** 첫 값의 시각 (epoch 초, UTC 정시) */
  start: number;
  /** start부터 1시간 간격 기온(°C, 소수 첫째 자리). 값이 없는 시간은 null */
  temps: Array<number | null>;
}

/** 하늘 상태에 쓰는 낮 시간 (현지 시, 끝 제외) */
export const DAYTIME_HOURS = { from: 8, to: 20 } as const;
/** 운량·적설은 그 시간의 이 비율 이상 값이 있을 때만 구한다 */
const MIN_COVERAGE = 0.75;

export interface TripRain {
  /** 계열마다 그 날 최고 강수확률의 가중 평균 (aggregateDay) */
  pop: number;
  agreeing: number;
  total: number;
  rainy: boolean;
}

/** 한 장소의 하루 날씨. 하루 경계는 그 장소의 시간대다. */
export interface TripDayWeather {
  /** 그 장소 현지 날짜의 0시 (epoch 초) */
  start: number;
  /** 남은 시간의 비 소식. 이미 지난 날이거나 예보가 닿지 않으면 null */
  rain: TripRain | null;
  /** 낮(DAYTIME_HOURS) 평균 운량(%) */
  cloud: number | null;
  /** 하루 적설(cm), 모델 평균 */
  snowCm: number | null;
  /** 0–24시 시간별 기온. 그 날 끝까지 닿는 Open-Meteo 모델의 평균 (providers에 쓴 모델) */
  temps: TempHistory | null;
}

/** Open-Meteo 모델 예보와 그 모델의 기온이 닿는 마지막 시각 */
export interface ModelReach {
  forecast: ProviderForecast;
  reach: number;
}

/** Open-Meteo 모델마다 기온이 닿는 마지막 시각. 날짜마다 다시 구하지 않게 한 번만 구한다. */
export function openMeteoReach(forecasts: ProviderForecast[]): ModelReach[] {
  return forecasts.filter((f) => OPEN_METEO_PROVIDERS.has(f.provider)).map((forecast) => {
    let reach = -Infinity;
    for (const s of forecast.slots) if (s.temp !== null && s.t > reach) reach = s.t;
    return { forecast, reach };
  });
}

/**
 * 하루 [from, to): 그 날 마지막 정시까지 기온이 닿는 모델(먼 날일수록 줄어든다)과 그 모델들의 시간별 평균 기온.
 * 닿는 모델이 없으면 temps는 null.
 */
export function coveringDay(
  models: ModelReach[],
  range: { from: number; to: number },
): { covering: ProviderForecast[]; temps: TempHistory | null } {
  const lastHour = Math.floor((range.to - 1) / 3600) * 3600;
  const covering = models.filter((m) => m.reach >= lastHour).map((m) => m.forecast);
  return { covering, temps: covering.length > 0 ? meanTempSeries(covering, range) : null };
}

/**
 * [from, to)의 정시마다 Open-Meteo 모델 평균 기온(앞뒤 빈 시간은 잘라 낸다).
 * 값이 가장 많은 모델의 TEMP_HISTORY_MIN_COVERAGE보다 적게 가진 모델은 뺀다.
 * 한 소스라도 빠진 시간은 평균의 구성이 달라지므로 비워 둔다.
 */
export function meanTempSeries(
  forecasts: ProviderForecast[],
  range: { from: number; to: number },
): TempHistory | null {
  const from = Math.ceil(range.from / 3600) * 3600;
  const to = range.to;
  const series = forecasts.filter((f) => OPEN_METEO_PROVIDERS.has(f.provider)).map((f) => ({
    provider: f.provider,
    temps: new Map(
      f.slots.filter((s) => s.temp !== null && s.t >= from && s.t < to).map((s) => [s.t, s.temp!]),
    ),
  }));
  const most = Math.max(0, ...series.map((s) => s.temps.size));
  if (most === 0) return null;
  const used = series.filter((s) => s.temps.size >= most * TEMP_HISTORY_MIN_COVERAGE);

  const temps: Array<number | null> = [];
  for (let t = from; t < to; t += 3600) {
    const values = used.map((s) => s.temps.get(t));
    temps.push(
      values.every((v) => v !== undefined)
        ? Math.round(values.reduce((a, b) => a + b!, 0) / values.length * 10) / 10
        : null,
    );
  }
  const first = temps.findIndex((v) => v !== null);
  if (first < 0) return null;
  const last = temps.findLastIndex((v) => v !== null);
  return {
    providers: used.map((s) => s.provider),
    start: from + first * 3600,
    temps: temps.slice(first, last + 1),
  };
}

/** 한 장소의 예보로 날짜별 하루 날씨를 만든다. 같은 날짜는 한 번만 계산한다. */
export class DayWeatherBuilder {
  private readonly models: ModelReach[];
  private readonly memo = new Map<string, TripDayWeather>();

  constructor(
    private readonly forecasts: ProviderForecast[],
    private readonly opts: { tz: string; nowSec: number; threshold: number },
  ) {
    this.models = openMeteoReach(forecasts);
  }

  day(date: string): TripDayWeather {
    let weather = this.memo.get(date);
    if (!weather) {
      weather = this.build(parseLocalDate(date));
      this.memo.set(date, weather);
    }
    return weather;
  }

  private build(date: LocalDate): TripDayWeather {
    const { tz, nowSec, threshold } = this.opts;
    const start = zonedEpoch(date, 0, 0, tz);
    const end = zonedEpoch(addDays(date, 1), 0, 0, tz);

    const from = Math.max(start, Math.floor(nowSec / 3600) * 3600);
    let rain: TripRain | null = null;
    if (from < end) {
      const agg = aggregateDay(this.forecasts, { from, to: end, threshold });
      if (agg.pop !== null) {
        rain = { pop: agg.pop, agreeing: agg.agreeing, total: agg.total, rainy: agg.rainy };
      }
    }

    // 그 날 마지막 정시까지 기온이 있는 모델만 (먼 날일수록 줄어든다)
    const { covering, temps } = coveringDay(this.models, { from: start, to: end });
    const hours: number[] = [];
    for (let t = Math.ceil(start / 3600) * 3600; t < end; t += 3600) hours.push(t);

    return {
      start,
      rain,
      cloud: daytimeCloud(covering, hours, start),
      snowCm: dailySnow(covering, hours),
      temps,
    };
  }
}

/** 낮 시간마다 모델 평균 운량을 구하고, 그 평균. 값이 있는 시간이 모자라면 null */
function daytimeCloud(models: ProviderForecast[], hours: number[], start: number): number | null {
  const daytime = hours.filter((t) => {
    const h = (t - start) / 3600;
    return h >= DAYTIME_HOURS.from && h < DAYTIME_HOURS.to;
  });
  const bySlot = models.map((f) => new Map(f.slots.map((s) => [s.t, s.cloud ?? null])));
  const means: number[] = [];
  for (const t of daytime) {
    const values = bySlot.map((m) => m.get(t)).filter((v): v is number => v != null);
    if (values.length > 0) means.push(values.reduce((a, b) => a + b, 0) / values.length);
  }
  if (means.length === 0 || means.length < daytime.length * MIN_COVERAGE) return null;
  return Math.round(means.reduce((a, b) => a + b, 0) / means.length);
}

/** 모델마다 하루 적설 합(값이 충분한 모델만)을 구해 평균 (cm, 소수 첫째 자리) */
function dailySnow(models: ProviderForecast[], hours: number[]): number | null {
  const wanted = new Set(hours);
  const sums: number[] = [];
  for (const f of models) {
    const values = f.slots.filter((s) => wanted.has(s.t) && s.snowCm != null).map((s) => s.snowCm!);
    if (values.length > 0 && values.length >= hours.length * MIN_COVERAGE) {
      sums.push(values.reduce((a, b) => a + b, 0));
    }
  }
  if (sums.length === 0) return null;
  return Math.round(sums.reduce((a, b) => a + b, 0) / sums.length * 10) / 10;
}
