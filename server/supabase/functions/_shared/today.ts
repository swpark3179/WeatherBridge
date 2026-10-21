/**
 * 앱 "오늘"·"비교" 화면과 요약 알림이 쓰는 사용자별 예보 묶음.
 * 응답 형식은 ios/Packages/WeatherCore의 TodayResponse와 같고, 계약 샘플
 * ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/today_response.json을 양쪽 테스트가 검증한다.
 * 좌표는 싣지 않는다.
 */
import { aggregate, aggregateDay, type RainWindow } from "./aggregate.ts";
import { type Briefing, buildBriefing, restOfLocalDay } from "./briefing.ts";
import type { Place, PlaceKind } from "./db.ts";
import { type Deps, ensureForecasts } from "./forecast_service.ts";
import type { Family, ProviderForecast, ProviderId } from "./forecast_types.ts";
import { OPEN_METEO_MODELS } from "./providers/open_meteo.ts";
import { addDays, localDateOf, zonedEpoch } from "./schedule.ts";

export const DEFAULT_THRESHOLD = 30;
const HORIZON_HOURS = 48;
/** 기온 비교에 싣는 지난 날 수 (어제 ~ 7일 전) */
export const TEMP_HISTORY_DAYS = 7;
/** 값이 가장 많은 소스의 이 비율보다 적게 가진 소스는 기온 평균에서 뺀다 */
const TEMP_HISTORY_MIN_COVERAGE = 0.9;
/** 7일 보기: 오늘부터 실을 현지 날짜 수 */
export const DAILY_DAYS = 7;

export interface LoadedPlace {
  place: Place;
  forecasts: ProviderForecast[];
  errors: string[];
}

export interface TodayHour {
  t: number;
  consensus: number | null;
  min: number | null;
  max: number | null;
  agreeing: number;
  total: number;
  split: boolean;
  rainy: boolean;
  temp: number | null;
  families: Partial<Record<Family, number>>;
  providers: Partial<Record<ProviderId, number>>;
}

export interface TodayPlace {
  id: string;
  kind: PlaceKind;
  name: string;
  maxPop: number;
  highlight: boolean;
  windows: RainWindow[];
  hours: TodayHour[];
  sources: Array<{ provider: ProviderId; family: Family; issuedAt: number; fetchedAt: number }>;
  errors: string[];
  /** 기온 비교용 시간별 기온. 지난 값을 주는 소스가 없으면 null */
  tempHistory: TempHistory | null;
  /** 7일 보기: 오늘부터 날짜별 비 소식. 쓸 예보가 없는 날은 빠진다 */
  days: TodayDay[];
}

/** 하루 비 소식 (aggregate.ts aggregateDay). 시간대 없이 그 날 비가 오는지만 본다. */
export interface TodayDay {
  /** 현지 날짜의 0시 (epoch 초). 오늘은 지금 시각이 속한 시간부터 계산한다 */
  date: number;
  /** 계열마다 그 날 가장 높은 강수확률의 가중 평균 */
  pop: number;
  agreeing: number;
  total: number;
  rainy: boolean;
}

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

export interface TodayResponse {
  generatedAt: number;
  tz: string;
  threshold: number;
  /** 오늘 남은 시간 기준 (요약 알림·잠금화면과 같은 문구) */
  briefing: Briefing;
  /** 집, 회사 순서. 앞으로 horizonHours시간 */
  places: TodayPlace[];
}

const KIND_ORDER: Record<PlaceKind, number> = { home: 0, office: 1, trip: 2 };

/** 지난 값도 주는 소스 (기온 비교·여행 기온은 이 모델들끼리만 평균한다) */
export const OPEN_METEO_PROVIDERS: ReadonlySet<ProviderId> = new Set(
  Object.values(OPEN_METEO_MODELS),
);

/** 장소별 예보를 캐시에서 꺼낸다(만료됐으면 새로 받음). 집, 회사 순서로 돌려준다. */
export async function loadForecasts(deps: Deps, places: Place[]): Promise<LoadedPlace[]> {
  const sorted = [...places].sort((a, b) => KIND_ORDER[a.kind] - KIND_ORDER[b.kind]);
  const loaded: LoadedPlace[] = [];
  for (const place of sorted) {
    const { forecasts, errors } = await ensureForecasts(place, deps);
    loaded.push({ place, forecasts, errors });
  }
  return loaded;
}

/**
 * TEMP_HISTORY_DAYS일 전 현지 자정부터 오늘 자정까지의 시간별 기온(앞뒤 빈 시간은 잘라 낸다).
 * 지난 값도 주는 Open-Meteo 모델만 쓴다(기상청 단기예보는 지난 시간이 없다).
 */
export function tempHistory(
  forecasts: ProviderForecast[],
  opts: { nowSec: number; tz: string },
): TempHistory | null {
  const today = localDateOf(opts.nowSec, opts.tz);
  return meanTempSeries(forecasts, {
    from: zonedEpoch(addDays(today, -TEMP_HISTORY_DAYS), 0, 0, opts.tz),
    to: zonedEpoch(addDays(today, 1), 0, 0, opts.tz),
  });
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

/** 오늘부터 DAILY_DAYS개 현지 날짜의 비 소식. 오늘은 지금 시각이 속한 시간부터 자정까지 본다. */
export function dailyRain(
  forecasts: ProviderForecast[],
  opts: { nowSec: number; tz: string; threshold: number },
): TodayDay[] {
  const today = localDateOf(opts.nowSec, opts.tz);
  const days: TodayDay[] = [];
  for (let i = 0; i < DAILY_DAYS; i++) {
    const date = zonedEpoch(addDays(today, i), 0, 0, opts.tz);
    const from = i === 0 ? Math.floor(opts.nowSec / 3600) * 3600 : date;
    const to = zonedEpoch(addDays(today, i + 1), 0, 0, opts.tz);
    const { pop, agreeing, total, rainy } = aggregateDay(forecasts, {
      from,
      to,
      threshold: opts.threshold,
    });
    if (pop !== null) days.push({ date, pop, agreeing, total, rainy });
  }
  return days;
}

/** 오늘 남은 시간 브리핑 (요약 알림 문구) */
export function userBriefing(
  loaded: LoadedPlace[],
  opts: { nowSec: number; tz: string; threshold: number },
): Briefing {
  const range = restOfLocalDay(opts.nowSec, opts.tz);
  return buildBriefing({
    nowSec: opts.nowSec,
    tz: opts.tz,
    places: loaded.map(({ place, forecasts }) => ({
      name: place.name,
      aggregate: aggregate(forecasts, { ...range, threshold: opts.threshold }),
    })),
  });
}

export function buildToday(
  loaded: LoadedPlace[],
  opts: { nowSec: number; tz: string; threshold: number; horizonHours?: number },
): TodayResponse {
  const from = Math.floor(opts.nowSec / 3600) * 3600;
  const to = from + (opts.horizonHours ?? HORIZON_HOURS) * 3600;
  return {
    generatedAt: opts.nowSec,
    tz: opts.tz,
    threshold: opts.threshold,
    briefing: userBriefing(loaded, opts),
    places: loaded.map(({ place, forecasts, errors }) => {
      const agg = aggregate(forecasts, { from, to, threshold: opts.threshold });
      return {
        id: place.id,
        kind: place.kind,
        name: place.name,
        maxPop: agg.maxPop,
        highlight: agg.highlight,
        windows: agg.windows,
        // 등급(level)은 앱이 RainLevel(pop:)으로 계산하고, 예보 범위 경계(bandChange)는 아직 쓰지 않는다.
        hours: agg.hours.map((h) => ({
          t: h.t,
          consensus: h.consensus,
          min: h.min,
          max: h.max,
          agreeing: h.agreeing,
          total: h.total,
          split: h.split,
          rainy: h.rainy,
          temp: h.temp,
          families: h.families,
          providers: h.providers,
        })),
        sources: forecasts.map((f) => ({
          provider: f.provider,
          family: f.family,
          issuedAt: f.issuedAt,
          fetchedAt: f.fetchedAt,
        })),
        errors,
        tempHistory: tempHistory(forecasts, opts),
        days: dailyRain(forecasts, opts),
      };
    }),
  };
}
