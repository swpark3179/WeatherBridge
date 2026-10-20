/** 배포 환경에서 쓰는 의존성과 장소 조회 */
import type { ApnsConfig } from "./dispatch.ts";
import { type Place, type PlaceKind, supabaseRepo } from "./db.ts";
import type { Deps } from "./forecast_service.ts";

export function liveDeps(): Deps {
  return {
    repo: supabaseRepo(),
    nowMs: () => Date.now(),
    kmaServiceKey: Deno.env.get("KMA_SERVICE_KEY") || undefined,
  };
}

/** 함수 시크릿의 APNs 키. 하나라도 없으면 null. */
export function apnsConfigFromEnv(): ApnsConfig | null {
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const privateKeyPem = Deno.env.get("APNS_P8");
  if (!teamId || !keyId || !privateKeyPem) return null;
  return {
    key: { teamId, keyId, privateKeyPem },
    bundleId: Deno.env.get("APNS_BUNDLE_ID") ?? "io.github.swpark3179.weatherbridge",
  };
}

/** 운영자가 SQL로 등록한 점검용 장소(user_id 없음). 운영 토큰 함수(forecast·briefing)는 이것만 쓴다. */
export async function operatorPlaces(deps: Deps): Promise<Place[]> {
  return (await deps.repo.listActivePlaces()).filter((p) => p.userId === null);
}

/** `?place_id=` 또는 `?kind=home|office`로 운영 장소를 찾는다. kind는 가장 먼저 등록된 활성 장소. */
export async function findPlace(deps: Deps, url: URL): Promise<Place | null> {
  const places = await operatorPlaces(deps);
  const id = url.searchParams.get("place_id");
  if (id) return places.find((p) => p.id === id) ?? null;
  const kind = (url.searchParams.get("kind") ?? "home") as PlaceKind;
  return places.find((p) => p.kind === kind) ?? null;
}

/** 응답에 좌표를 싣지 않는다 */
export function publicPlace(p: Place) {
  return { id: p.id, kind: p.kind, name: p.name, tz: p.tz };
}
