/**
 * 저장소. Edge Function에서는 Supabase(서비스 키), 테스트에서는 MemoryRepo를 쓴다.
 * 테이블 정의: server/supabase/migrations/20261018000000_forecast_core.sql, 20261020000000_phase2_users.sql
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { HourSlot, Observation, ProviderForecast, ProviderId } from "./forecast_types.ts";

export type PlaceKind = "home" | "office" | "trip";

export interface Place {
  id: string;
  /** 앱 사용자. null이면 운영자가 SQL로 등록한 점검용 장소 */
  userId: string | null;
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

export interface UserSettings {
  userId: string;
  tz: string;
  summaryEnabled: boolean;
  /** 현지 시각 "HH:MM" */
  summaryTime: string;
  /** 강수 강조 임계값(%) */
  threshold: number;
}

export type ApnsEnvName = "sandbox" | "production";

export interface Device {
  id: string;
  userId: string;
  apnsToken: string;
  apnsEnv: ApnsEnvName;
}

/** 점검용 기기 정보. 토큰 값은 담지 않는다. */
export interface DeviceStatus {
  id: string;
  userId: string;
  apnsEnv: ApnsEnvName;
  hasPushToStart: boolean;
  appVersion: string | null;
  active: boolean;
  deactivatedReason: string | null;
  /** 마지막으로 앱이 기기를 등록한 시각 (epoch 초) */
  lastSeenAt: number;
}

/** 실험실 발송용 토큰 */
export interface LatestDevice {
  id: string;
  apnsToken: string;
  pushToStartToken: string | null;
}

export type DispatchKind = "summary";
export type DispatchStatus = "pending" | "sent" | "retry" | "failed" | "skipped";

export interface DispatchKey {
  userId: string;
  kind: DispatchKind;
  /** 현지 날짜 "YYYY-MM-DD" */
  localDate: string;
  /** 예정 시각 (epoch 초) */
  scheduledAt: number;
}

export interface DispatchRecord extends DispatchKey {
  status: DispatchStatus;
  attempts: number;
  detail: unknown;
  /** 마지막으로 바뀐 시각 (epoch 초). 끝난 기록이면 발송을 마친 시각이다. */
  updatedAt: number;
}

export interface DispatchClaim {
  id: number;
  attempts: number;
}

/** 발송 중(pending)인 채로 이만큼 지나면 함수가 중간에 멈춘 것으로 보고 다시 시도한다 */
export const STALE_PENDING_SEC = 10 * 60;

export interface Repo {
  /** 모든 활성 장소(앱 사용자 + 운영자). refresh가 쓴다. */
  listActivePlaces(): Promise<Place[]>;
  /** 사용자의 활성 집·회사 */
  listUserPlaces(userId: string): Promise<Place[]>;
  getUserSettings(userId: string): Promise<UserSettings | null>;
  /** 요약 알림을 켠 사용자 */
  listSummaryCandidates(): Promise<UserSettings[]>;
  /**
   * 발송 권한을 얻는다. 처음이면 기록을 만들고, 재시도 대기(retry) 또는 멈춘 발송(pending)이면
   * 시도 횟수를 올린다. 이미 끝났거나 다른 실행이 처리 중이면 null.
   */
  claimDispatch(key: DispatchKey, maxAttempts: number): Promise<DispatchClaim | null>;
  finishDispatch(id: number, status: DispatchStatus, detail: unknown): Promise<void>;
  listActiveDevices(userId: string): Promise<Device[]>;
  deactivateDevice(id: string, reason: string): Promise<void>;
  /** 점검용: 최근에 등록된 기기부터 */
  listRecentDevices(limit: number): Promise<DeviceStatus[]>;
  /** 실험실 발송용: 그 환경에서 가장 최근에 등록된 활성 기기 */
  latestDevice(env: ApnsEnvName): Promise<LatestDevice | null>;
  /** 점검용: 예정 시각이 늦은 기록부터 */
  listRecentDispatches(limit: number): Promise<DispatchRecord[]>;
  getProviderToken(keyId: string): Promise<{ token: string; issuedAt: number } | null>;
  putProviderToken(keyId: string, token: string, issuedAt: number): Promise<void>;
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

const PLACE_COLUMNS = "id, user_id, kind, name, lat, lon, tz, kma_nx, kma_ny";
const SETTINGS_COLUMNS = "user_id, tz, summary_enabled, summary_time, threshold";

// deno-lint-ignore no-explicit-any
function toPlace(r: any): Place {
  return {
    id: r.id,
    userId: r.user_id,
    kind: r.kind,
    name: r.name,
    lat: Number(r.lat),
    lon: Number(r.lon),
    tz: r.tz,
    kmaNx: r.kma_nx,
    kmaNy: r.kma_ny,
  };
}

// deno-lint-ignore no-explicit-any
function toSettings(r: any): UserSettings {
  return {
    userId: r.user_id,
    tz: r.tz,
    summaryEnabled: r.summary_enabled,
    summaryTime: String(r.summary_time).slice(0, 5),
    threshold: r.threshold,
  };
}

function reclaimable(status: string, attempts: number, updatedAt: number, maxAttempts: number) {
  if (attempts >= maxAttempts) return false;
  if (status === "retry") return true;
  return status === "pending" && Date.now() / 1000 - updatedAt >= STALE_PENDING_SEC;
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
        await db.from("places").select(PLACE_COLUMNS).eq("active", true).order("created_at"),
      ) ?? [];
      return rows.map(toPlace);
    },
    async listUserPlaces(userId) {
      const rows = check(
        await db.from("places").select(PLACE_COLUMNS).eq("user_id", userId).eq("active", true)
          .in("kind", ["home", "office"]).order("created_at"),
      ) ?? [];
      return rows.map(toPlace);
    },
    async getUserSettings(userId) {
      const row = check(
        await db.from("user_settings").select(SETTINGS_COLUMNS).eq("user_id", userId)
          .maybeSingle(),
      );
      return row ? toSettings(row) : null;
    },
    async listSummaryCandidates() {
      const rows = check(
        await db.from("user_settings").select(SETTINGS_COLUMNS).eq("summary_enabled", true),
      ) ?? [];
      return rows.map(toSettings);
    },
    async claimDispatch(key, maxAttempts) {
      const inserted = check(
        await db.from("dispatch_log").upsert({
          user_id: key.userId,
          kind: key.kind,
          local_date: key.localDate,
          scheduled_at: iso(key.scheduledAt),
          status: "pending",
          attempts: 1,
        }, { onConflict: "user_id,kind,local_date", ignoreDuplicates: true }).select(
          "id, attempts",
        ),
      ) ?? [];
      if (inserted.length > 0) return { id: inserted[0].id, attempts: inserted[0].attempts };

      const row = check(
        await db.from("dispatch_log").select("id, status, attempts, updated_at")
          .eq("user_id", key.userId).eq("kind", key.kind).eq("local_date", key.localDate)
          .maybeSingle(),
      );
      if (!row || !reclaimable(row.status, row.attempts, sec(row.updated_at), maxAttempts)) {
        return null;
      }
      // 같은 상태·시도 횟수일 때만 바꿔서, 동시에 실행된 두 함수 중 하나만 권한을 얻는다.
      const updated = check(
        await db.from("dispatch_log").update({
          status: "pending",
          attempts: row.attempts + 1,
          updated_at: new Date().toISOString(),
        }).eq("id", row.id).eq("status", row.status).eq("attempts", row.attempts).select("id"),
      ) ?? [];
      return updated.length > 0 ? { id: row.id, attempts: row.attempts + 1 } : null;
    },
    async finishDispatch(id, status, detail) {
      check(
        await db.from("dispatch_log").update({
          status,
          detail,
          updated_at: new Date().toISOString(),
        }).eq("id", id),
      );
    },
    async listActiveDevices(userId) {
      const rows = check(
        await db.from("devices").select("id, user_id, apns_token, apns_env").eq("user_id", userId)
          .eq("active", true),
      ) ?? [];
      return rows.map((r) => ({
        id: r.id,
        userId: r.user_id,
        apnsToken: r.apns_token,
        apnsEnv: r.apns_env,
      }));
    },
    async deactivateDevice(id, reason) {
      check(
        await db.from("devices").update({ active: false, deactivated_reason: reason }).eq("id", id),
      );
    },
    async listRecentDevices(limit) {
      const rows = check(
        await db.from("devices").select(
          "id, user_id, apns_env, push_to_start_token, app_version, active, deactivated_reason, last_seen_at",
        ).order("last_seen_at", { ascending: false }).limit(limit),
      ) ?? [];
      return rows.map((r) => ({
        id: r.id,
        userId: r.user_id,
        apnsEnv: r.apns_env,
        hasPushToStart: Boolean(r.push_to_start_token),
        appVersion: r.app_version,
        active: r.active,
        deactivatedReason: r.deactivated_reason,
        lastSeenAt: sec(r.last_seen_at),
      }));
    },
    async latestDevice(env) {
      const row = check(
        await db.from("devices").select("id, apns_token, push_to_start_token").eq("apns_env", env)
          .eq("active", true).order("last_seen_at", { ascending: false }).limit(1).maybeSingle(),
      );
      return row
        ? { id: row.id, apnsToken: row.apns_token, pushToStartToken: row.push_to_start_token }
        : null;
    },
    async listRecentDispatches(limit) {
      const rows = check(
        await db.from("dispatch_log").select(
          "user_id, kind, local_date, scheduled_at, status, attempts, detail, updated_at",
        ).order("scheduled_at", { ascending: false }).limit(limit),
      ) ?? [];
      return rows.map((r) => ({
        userId: r.user_id,
        kind: r.kind,
        localDate: r.local_date,
        scheduledAt: sec(r.scheduled_at),
        status: r.status,
        attempts: r.attempts,
        detail: r.detail,
        updatedAt: sec(r.updated_at),
      }));
    },
    async getProviderToken(keyId) {
      const row = check(
        await db.from("apns_provider_token").select("token, issued_at").eq("key_id", keyId)
          .maybeSingle(),
      );
      return row ? { token: row.token, issuedAt: sec(row.issued_at) } : null;
    },
    async putProviderToken(keyId, token, issuedAt) {
      check(
        await db.from("apns_provider_token").upsert({
          key_id: keyId,
          token,
          issued_at: iso(issuedAt),
        }),
      );
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

interface MemoryDispatch extends DispatchRecord {
  id: number;
}

/** 테스트에서 넣는 기기. 점검용 값은 생략할 수 있다. */
type MemoryDevice = Device & {
  active: boolean;
  reason: string | null;
  pushToStartToken?: string | null;
  appVersion?: string | null;
  lastSeenAt?: number;
};

/** 테스트용 메모리 저장소 */
export class MemoryRepo implements Repo {
  places: Place[] = [];
  cache = new Map<string, CacheEntry>();
  logs: ForecastLogRow[] = [];
  observations = new Map<string, Observation>();
  settings: UserSettings[] = [];
  devices: MemoryDevice[] = [];
  dispatches: MemoryDispatch[] = [];
  providerTokens = new Map<string, { token: string; issuedAt: number }>();
  /** updatedAt 기록용 시계 (epoch 초) */
  clock = () => Math.floor(Date.now() / 1000);

  listActivePlaces() {
    return Promise.resolve(structuredClone(this.places));
  }
  listUserPlaces(userId: string) {
    return Promise.resolve(
      structuredClone(
        this.places.filter((p) =>
          p.userId === userId && (p.kind === "home" || p.kind === "office")
        ),
      ),
    );
  }
  getUserSettings(userId: string) {
    return Promise.resolve(structuredClone(this.settings.find((s) => s.userId === userId) ?? null));
  }
  listSummaryCandidates() {
    return Promise.resolve(structuredClone(this.settings.filter((s) => s.summaryEnabled)));
  }
  claimDispatch(key: DispatchKey, maxAttempts: number) {
    const row = this.dispatches.find((d) =>
      d.userId === key.userId && d.kind === key.kind && d.localDate === key.localDate
    );
    if (!row) {
      const id = this.dispatches.length + 1;
      this.dispatches.push({
        ...key,
        id,
        status: "pending",
        attempts: 1,
        detail: null,
        updatedAt: this.clock(),
      });
      return Promise.resolve({ id, attempts: 1 });
    }
    const stale = row.status === "pending" && this.clock() - row.updatedAt >= STALE_PENDING_SEC;
    if (row.attempts >= maxAttempts || (row.status !== "retry" && !stale)) {
      return Promise.resolve(null);
    }
    Object.assign(row, { status: "pending", attempts: row.attempts + 1, updatedAt: this.clock() });
    return Promise.resolve({ id: row.id, attempts: row.attempts });
  }
  finishDispatch(id: number, status: DispatchStatus, detail: unknown) {
    const row = this.dispatches.find((d) => d.id === id);
    if (row) {
      Object.assign(row, { status, detail: structuredClone(detail), updatedAt: this.clock() });
    }
    return Promise.resolve();
  }
  listActiveDevices(userId: string) {
    return Promise.resolve(
      this.devices.filter((d) => d.userId === userId && d.active).map((d) => ({
        id: d.id,
        userId: d.userId,
        apnsToken: d.apnsToken,
        apnsEnv: d.apnsEnv,
      })),
    );
  }
  deactivateDevice(id: string, reason: string) {
    const d = this.devices.find((d) => d.id === id);
    if (d) Object.assign(d, { active: false, reason });
    return Promise.resolve();
  }
  listRecentDevices(limit: number) {
    return Promise.resolve(
      this.devicesByLastSeen().slice(0, limit).map((d) => ({
        id: d.id,
        userId: d.userId,
        apnsEnv: d.apnsEnv,
        hasPushToStart: Boolean(d.pushToStartToken),
        appVersion: d.appVersion ?? null,
        active: d.active,
        deactivatedReason: d.reason,
        lastSeenAt: d.lastSeenAt ?? 0,
      })),
    );
  }
  latestDevice(env: ApnsEnvName) {
    const d = this.devicesByLastSeen().find((d) => d.apnsEnv === env && d.active);
    return Promise.resolve(
      d ? { id: d.id, apnsToken: d.apnsToken, pushToStartToken: d.pushToStartToken ?? null } : null,
    );
  }
  listRecentDispatches(limit: number) {
    return Promise.resolve(
      [...this.dispatches].sort((a, b) => b.scheduledAt - a.scheduledAt).slice(0, limit)
        .map(({ id: _id, ...rest }) => structuredClone(rest)),
    );
  }
  private devicesByLastSeen() {
    return [...this.devices].sort((a, b) => (b.lastSeenAt ?? 0) - (a.lastSeenAt ?? 0));
  }
  getProviderToken(keyId: string) {
    return Promise.resolve(this.providerTokens.get(keyId) ?? null);
  }
  putProviderToken(keyId: string, token: string, issuedAt: number) {
    this.providerTokens.set(keyId, { token, issuedAt });
    return Promise.resolve();
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
