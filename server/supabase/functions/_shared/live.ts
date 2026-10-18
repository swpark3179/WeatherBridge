/** 배포 환경에서 쓰는 의존성과 장소 조회 */
import { type Place, type PlaceKind, supabaseRepo } from "./db.ts";
import type { Deps } from "./forecast_service.ts";

export function liveDeps(): Deps {
  return {
    repo: supabaseRepo(),
    nowMs: () => Date.now(),
    kmaServiceKey: Deno.env.get("KMA_SERVICE_KEY") || undefined,
  };
}

/** `?place_id=` 또는 `?kind=home|office`로 장소를 찾는다. kind는 가장 먼저 등록된 활성 장소. */
export async function findPlace(deps: Deps, url: URL): Promise<Place | null> {
  const places = await deps.repo.listActivePlaces();
  const id = url.searchParams.get("place_id");
  if (id) return places.find((p) => p.id === id) ?? null;
  const kind = (url.searchParams.get("kind") ?? "home") as PlaceKind;
  return places.find((p) => p.kind === kind) ?? null;
}

/** 응답에 좌표를 싣지 않는다 */
export function publicPlace(p: Place) {
  return { id: p.id, kind: p.kind, name: p.name, tz: p.tz };
}
