/**
 * 장소별 예보 확보(캐시 우선)와 주기 수집(refresh). Edge Function들이 공유한다.
 */
import type { CacheEntry, Place, Repo } from "./db.ts";
import type { FetchFn, ProviderForecast, ProviderId } from "./forecast_types.ts";
import { isKmaCovered, type KmaGrid, kmaLocKey, toKmaGrid } from "./kma_grid.ts";
import { kstToEpoch, latestVilageBase, nextVilageAvailableAt } from "./kma_time.ts";
import { fetchKmaObservation, fetchKmaShort } from "./providers/kma.ts";
import { fetchOpenMeteo, OPEN_METEO_MODELS } from "./providers/open_meteo.ts";

export interface Deps {
  repo: Repo;
  nowMs: () => number;
  kmaServiceKey?: string;
  fetchFn?: FetchFn;
}

/** 기록에 남기는 예보 범위 */
const LOG_HORIZON_SEC = 72 * 3600;
/** Open-Meteo 캐시 수명. 매시 cron이 새로 받도록 1시간보다 조금 짧게. */
const OPEN_METEO_TTL_SEC = 55 * 60;

export function openMeteoLocKey(place: Pick<Place, "lat" | "lon">): string {
  return `ll:${place.lat.toFixed(2)}:${place.lon.toFixed(2)}`;
}

function placeGrid(place: Place): KmaGrid | null {
  if (!isKmaCovered(place.lat, place.lon)) return null;
  if (place.kmaNx !== null && place.kmaNy !== null) return { nx: place.kmaNx, ny: place.kmaNy };
  return toKmaGrid(place.lat, place.lon);
}

export interface EnsureResult {
  forecasts: ProviderForecast[];
  /** 이번 호출에서 새로 받은 소스 */
  fetched: ProviderId[];
  errors: string[];
}

/** 캐시가 유효하면 그대로, 만료됐으면 다시 받아 캐시에 저장한다. 실패한 소스는 오래된 캐시라도 쓴다. */
export async function ensureForecasts(place: Place, deps: Deps): Promise<EnsureResult> {
  const now = Math.floor(deps.nowMs() / 1000);
  const result: EnsureResult = { forecasts: [], fetched: [], errors: [] };
  const grid = placeGrid(place);

  if (grid && deps.kmaServiceKey) {
    const locKey = kmaLocKey(grid);
    const cached = await deps.repo.getCache("kma_short", locKey);
    if (cached && cached.expiresAt > now) {
      result.forecasts.push(cached.payload);
    } else {
      try {
        const f = await fetchKmaShort({
          serviceKey: deps.kmaServiceKey,
          grid,
          nowMs: deps.nowMs(),
          fetchFn: deps.fetchFn,
        });
        const expiresAt = nextVilageAvailableAt(latestVilageBase(deps.nowMs()));
        await deps.repo.putCache(toEntry(f, locKey, expiresAt));
        result.forecasts.push(f);
        result.fetched.push(f.provider);
      } catch (e) {
        result.errors.push(String(e));
        if (cached) result.forecasts.push(cached.payload);
      }
    }
  }

  const omKey = openMeteoLocKey(place);
  const omProviders = Object.values(OPEN_METEO_MODELS);
  const cached = await Promise.all(omProviders.map((p) => deps.repo.getCache(p, omKey)));
  if (cached.every((c) => c && c.expiresAt > now)) {
    result.forecasts.push(...cached.map((c) => c!.payload));
  } else {
    try {
      const fresh = await fetchOpenMeteo({
        lat: place.lat,
        lon: place.lon,
        nowMs: deps.nowMs(),
        fetchFn: deps.fetchFn,
      });
      for (const f of fresh) {
        await deps.repo.putCache(toEntry(f, omKey, now + OPEN_METEO_TTL_SEC));
        result.forecasts.push(f);
        result.fetched.push(f.provider);
      }
    } catch (e) {
      result.errors.push(String(e));
      result.forecasts.push(...cached.filter((c) => c !== null).map((c) => c!.payload));
    }
  }
  return result;
}

function toEntry(f: ProviderForecast, locKey: string, expiresAt: number): CacheEntry {
  return {
    provider: f.provider,
    locKey,
    issuedAt: f.issuedAt,
    fetchedAt: f.fetchedAt,
    expiresAt,
    payload: f,
  };
}

export interface RefreshSummary {
  places: number;
  fetched: string[];
  logged: number;
  observations: number;
  errors: string[];
}

/**
 * 주기 수집: 모든 활성 장소의 예보를 최신으로 맞추고, 기록(forecast_log, obs_log)을 남긴다.
 * 예보 기록은 기상청 발표 주기(3시간)에 맞춰 소스·위치별 1회만 남긴다.
 */
export async function refreshAll(deps: Deps): Promise<RefreshSummary> {
  const places = await deps.repo.listActivePlaces();
  const summary: RefreshSummary = {
    places: places.length,
    fetched: [],
    logged: 0,
    observations: 0,
    errors: [],
  };
  const now = Math.floor(deps.nowMs() / 1000);
  const base = latestVilageBase(deps.nowMs());
  const logBucket = kstToEpoch(base.baseDate, base.baseTime);
  const seenLoc = new Set<string>();
  const grids = new Map<string, KmaGrid>();

  for (const place of places) {
    const grid = placeGrid(place);
    if (grid && (place.kmaNx === null || place.kmaNy === null)) {
      await deps.repo.setPlaceGrid(place.id, grid.nx, grid.ny);
    }
    if (grid) grids.set(kmaLocKey(grid), grid);

    const { forecasts, fetched, errors } = await ensureForecasts(place, deps);
    summary.fetched.push(...fetched.map((p) => `${p}@${place.kind}`));
    summary.errors.push(...errors.map((e) => `${place.kind}: ${e}`));

    for (const f of forecasts) {
      const locKey = f.family === "kma" && grid ? kmaLocKey(grid) : openMeteoLocKey(place);
      const key = `${f.provider}|${locKey}`;
      if (seenLoc.has(key)) continue;
      seenLoc.add(key);
      const inserted = await deps.repo.insertForecastLog({
        provider: f.provider,
        locKey,
        issuedAt: f.family === "kma" ? f.issuedAt : logBucket,
        slots: f.slots
          .filter((s) => s.t >= now - 3600 && s.t < now + LOG_HORIZON_SEC && s.pop !== null)
          .map(({ t, pop, span }) => ({ t, pop, span })),
      });
      if (inserted) summary.logged++;
    }
  }

  if (deps.kmaServiceKey) {
    for (const grid of grids.values()) {
      try {
        const obs = await fetchKmaObservation({
          serviceKey: deps.kmaServiceKey,
          grid,
          nowMs: deps.nowMs(),
          fetchFn: deps.fetchFn,
        });
        await deps.repo.upsertObservation(obs);
        summary.observations++;
      } catch (e) {
        summary.errors.push(`obs ${kmaLocKey(grid)}: ${e}`);
      }
    }
  }
  return summary;
}
