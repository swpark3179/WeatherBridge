/**
 * 저장소. Edge Function에서는 Supabase(서비스 키), 테스트에서는 MemoryRepo를 쓴다.
 * 테이블 정의: server/supabase/migrations/20261018000000_forecast_core.sql
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { HourSlot, Observation, ProviderForecast, ProviderId } from "./forecast_types.ts";

export type PlaceKind = "home" | "office" | "trip";

export interface Place {
  id: string;
  kind: PlaceKind;
  name: string;
  lat: number;
  lon: number;
  tz: string;
  kmaNx: number | null;
  kmaNy: number | null;
}

export interface CacheEntry {
  provider: ProviderId;
  locKey: string;
  issuedAt: number;
  fetchedAt: number;
  expiresAt: number;
  payload: ProviderForecast;
}

export interface ForecastLogRow {
  provider: ProviderId;
  locKey: string;
  issuedAt: number;
  slots: Pick<HourSlot, "t" | "pop" | "span">[];
}

export interface Repo {
  listActivePlaces(): Promise<Place[]>;
  setPlaceGrid(id: string, nx: number, ny: number): Promise<void>;
  getCache(provider: ProviderId, locKey: string): Promise<CacheEntry | null>;
  putCache(entry: CacheEntry): Promise<void>;
  /** 같은 (provider, locKey, issuedAt)가 이미 있으면 기록하지 않고 false */
  insertForecastLog(row: ForecastLogRow): Promise<boolean>;
  upsertObservation(obs: Observation): Promise<void>;
}

const iso = (sec: number) => new Date(sec * 1000).toISOString();
const sec = (isoString: string) => Math.floor(Date.parse(isoString) / 1000);

/** 새 API 키 체계의 비밀 키(sb_secret_…). 폐기 예정인 service_role 키는 쓰지 않는다. */
function secretKey(): string {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!raw) throw new Error("SUPABASE_SECRET_KEYS 환경 변수가 없습니다");
  const key = (JSON.parse(raw) as Record<string, string>)["default"];
  if (!key) throw new Error("SUPABASE_SECRET_KEYS에 default 키가 없습니다");
  return key;
}

export function supabaseRepo(client?: SupabaseClient): Repo {
  const db = client ??
    createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

  const check = <T>(r: { data: T; error: { message: string } | null }): T => {
    if (r.error) throw new Error(r.error.message);
    return r.data;
  };

  return {
    async listActivePlaces() {
      const rows = check(
        await db.from("places").select("id, kind, name, lat, lon, tz, kma_nx, kma_ny")
          .eq("active", true).order("created_at"),
      ) ?? [];
      return rows.map((r) => ({
        id: r.id,
        kind: r.kind,
        name: r.name,
        lat: Number(r.lat),
        lon: Number(r.lon),
        tz: r.tz,
        kmaNx: r.kma_nx,
        kmaNy: r.kma_ny,
      }));
    },
    async setPlaceGrid(id, nx, ny) {
      check(await db.from("places").update({ kma_nx: nx, kma_ny: ny }).eq("id", id));
    },
    async getCache(provider, locKey) {
      const row = check(
        await db.from("forecast_cache").select("*").eq("provider", provider)
          .eq("loc_key", locKey).maybeSingle(),
      );
      if (!row) return null;
      return {
        provider: row.provider,
        locKey: row.loc_key,
        issuedAt: sec(row.issued_at),
        fetchedAt: sec(row.fetched_at),
        expiresAt: sec(row.expires_at),
        payload: row.payload,
      };
    },
    async putCache(e) {
      check(
        await db.from("forecast_cache").upsert({
          provider: e.provider,
          loc_key: e.locKey,
          issued_at: iso(e.issuedAt),
          fetched_at: iso(e.fetchedAt),
          expires_at: iso(e.expiresAt),
          payload: e.payload,
        }),
      );
    },
    async insertForecastLog(row) {
      const inserted = check(
        await db.from("forecast_log").upsert({
          provider: row.provider,
          loc_key: row.locKey,
          issued_at: iso(row.issuedAt),
          slots: row.slots,
        }, { onConflict: "provider,loc_key,issued_at", ignoreDuplicates: true }).select("id"),
      );
      return (inserted?.length ?? 0) > 0;
    },
    async upsertObservation(o) {
      check(
        await db.from("obs_log").upsert({
          loc_key: o.locKey,
          obs_time: iso(o.obsTime),
          rn1: o.rn1,
          pty: o.pty,
          t1h: o.t1h,
        }),
      );
    },
  };
}

/** 테스트용 메모리 저장소 */
export class MemoryRepo implements Repo {
  places: Place[] = [];
  cache = new Map<string, CacheEntry>();
  logs: ForecastLogRow[] = [];
  observations = new Map<string, Observation>();

  listActivePlaces() {
    return Promise.resolve(structuredClone(this.places));
  }
  setPlaceGrid(id: string, nx: number, ny: number) {
    const p = this.places.find((p) => p.id === id);
    if (p) Object.assign(p, { kmaNx: nx, kmaNy: ny });
    return Promise.resolve();
  }
  getCache(provider: ProviderId, locKey: string) {
    return Promise.resolve(this.cache.get(`${provider}|${locKey}`) ?? null);
  }
  putCache(entry: CacheEntry) {
    this.cache.set(`${entry.provider}|${entry.locKey}`, structuredClone(entry));
    return Promise.resolve();
  }
  insertForecastLog(row: ForecastLogRow) {
    const dup = this.logs.some((l) =>
      l.provider === row.provider && l.locKey === row.locKey && l.issuedAt === row.issuedAt
    );
    if (!dup) this.logs.push(structuredClone(row));
    return Promise.resolve(!dup);
  }
  upsertObservation(obs: Observation) {
    this.observations.set(`${obs.locKey}|${obs.obsTime}`, structuredClone(obs));
    return Promise.resolve();
  }
}
