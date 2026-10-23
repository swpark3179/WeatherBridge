/**
 * 앱 "오늘"·"비교" 화면과 요약 알림이 쓰는 사용자별 예보 묶음.
 * 응답 형식은 ios/Packages/WeatherCore의 TodayResponse와 같고, 계약 샘플
 * ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/today_response.json을 양쪽 테스트가 검증한다.
 * 좌표는 싣지 않는다.
 */
import { aggregate, aggregateDay, type RainWindow } from "./aggregate.ts";
import { type Briefing, buildBriefing, restOfLocalDay } from "./briefing.ts";
import type { Place, PlaceKind } from "./db.ts";
import {
  coveringDay,
  meanTempSeries,
  OPEN_METEO_PROVIDERS,
  openMeteoReach,
  type TempHistory,
} from "./day_weather.ts";
import { type Deps, ensureForecasts } from "./forecast_service.ts";
import type { Family, ProviderForecast, ProviderId } from "./forecast_types.ts";
import { addDays, localDateOf, zonedEpoch } from "./schedule.ts";

export const DEFAULT_THRESHOLD = 30;
const HORIZON_HOURS = 48;
/** 기온 비교에 싣는 지난 날 수 (어제 ~ 7일 전) */
export const TEMP_HISTORY_DAYS = 7;
/** 7일 보기: 오늘부터 실을 현지 날짜 수 */
export const DAILY_DAYS = 7;
/** 7일 보기 기온 비교의 기준 날 수(어제·그제·3일 전). 앱 HomeBaseline.days와 같다 */
export const RECENT_DAYS = 3;

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
  /**
   * 최근 RECENT_DAYS일(오늘 빼고)의 시간별 기온, Open-Meteo 모델마다 하나씩(providers에 그 모델 하나).
   * 앱이 7일 보기의 날마다 그 날과 같은 모델 묶음으로 기준을 만든다. 지난 값이 없는 모델은 빠진다.
   */
  recentTemps: TempHistory[];
  /** 7일 보기: 오늘부터 날짜별 비 소식과 하루 기온. 쓸 비 예보가 없는 날은 빠진다 */
  days: TodayDay[];
}

/** 하루 비 소식 (aggregate.ts aggregateDay)과 하루 기온. 시간대 없이 그 날 비가 오는지만 본다. */
export interface TodayDay {
  /** 현지 날짜의 0시 (epoch 초). 비 소식은 오늘이면 지금 시각이 속한 시간부터 계산한다 */
  date: number;
  /** 계열마다 그 날 가장 높은 강수확률의 가중 평균 */
  pop: number;
  agreeing: number;
  total: number;
  rainy: boolean;
  /**
   * 그 날 0–24시 시간별 기온(오늘도 지난 시간 포함). 그 날 끝까지 닿는 Open-Meteo 모델의 평균이고
   * providers에 쓴 모델을 싣는다. 닿는 모델이 없으면 null. 비 소식이 없어 빠진 날은 기온도 함께 빠지지만,
   * 비 소식과 기온은 같은 Open-Meteo 예보에서 나와 기온만 있는 날은 생기지 않는다.
   */
  temps: TempHistory | null;
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
 * 최근 RECENT_DAYS일(3일 전 0시 ~ 오늘 0시)의 시간별 기온, Open-Meteo 모델마다 하나씩.
 * 모델끼리 평균하지 않는다: 앱이 비교할 날과 같은 모델만 골라 평균한다(D24).
 */
export function recentTemps(
  forecasts: ProviderForecast[],
  opts: { nowSec: number; tz: string },
): TempHistory[] {
  const today = localDateOf(opts.nowSec, opts.tz);
  const range = {
    from: zonedEpoch(addDays(today, -RECENT_DAYS), 0, 0, opts.tz),
    to: zonedEpoch(today, 0, 0, opts.tz),
  };
  return forecasts.filter((f) => OPEN_METEO_PROVIDERS.has(f.provider))
    .map((f) => meanTempSeries([f], range))
    .filter((h): h is TempHistory => h !== null);
}

/**
 * 오늘부터 DAILY_DAYS개 현지 날짜의 비 소식과 하루 기온.
 * 비 소식은 오늘이면 지금 시각이 속한 시간부터 자정까지, 기온은 0시부터 자정까지 본다.
 */
export function dailyRain(
  forecasts: ProviderForecast[],
  opts: { nowSec: number; tz: string; threshold: number },
): TodayDay[] {
  const today = localDateOf(opts.nowSec, opts.tz);
  const models = openMeteoReach(forecasts);
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
    if (pop !== null) {
      const { temps } = coveringDay(models, { from: date, to });
      days.push({ date, pop, agreeing, total, rainy, temps });
    }
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
        recentTemps: recentTemps(forecasts, opts),
        days: dailyRain(forecasts, opts),
      };
    }),
  };
}
