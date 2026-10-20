/**
 * 앱 "오늘"·"비교" 화면과 요약 알림이 쓰는 사용자별 예보 묶음.
 * 응답 형식은 ios/Packages/WeatherCore의 TodayResponse와 같고, 계약 샘플
 * ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/today_response.json을 양쪽 테스트가 검증한다.
 * 좌표는 싣지 않는다.
 */
import { aggregate, type RainWindow } from "./aggregate.ts";
import { type Briefing, buildBriefing, restOfLocalDay } from "./briefing.ts";
import type { Place, PlaceKind } from "./db.ts";
import { type Deps, ensureForecasts } from "./forecast_service.ts";
import type { Family, ProviderForecast, ProviderId } from "./forecast_types.ts";

export const DEFAULT_THRESHOLD = 30;
const HORIZON_HOURS = 48;

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
      };
    }),
  };
}
