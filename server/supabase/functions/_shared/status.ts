/**
 * 실기기 점검 보고서: 기기 등록, 사용자별 요약 알림 설정, 최근 발송 기록.
 * 운영 토큰 함수 `ops-status`가 돌려준다. 좌표와 토큰 값은 담지 않고, ID는 앞 8자리만 쓴다.
 */
import type { ApnsEnvName, DispatchStatus, PlaceKind, Repo } from "./db.ts";

const short = (id: string) => id.slice(0, 8);

export interface StatusReport {
  now: number;
  devices: Array<{
    device: string;
    user: string;
    env: ApnsEnvName;
    pushToStart: boolean;
    appVersion: string | null;
    active: boolean;
    deactivatedReason: string | null;
    lastSeenAt: number;
  }>;
  /** 집·회사를 등록했거나 요약 알림을 켠 앱 사용자 */
  users: Array<{
    user: string;
    places: PlaceKind[];
    /** 요약 알림을 켜지 않았으면 null */
    summary: { time: string; tz: string; threshold: number } | null;
  }>;
  dispatches: Array<{
    user: string;
    localDate: string;
    scheduledAt: number;
    /** 끝난 기록(sent·failed·skipped)이면 마친 시각 */
    finishedAt: number | null;
    /** 보냈으면 예정 시각부터 APNs가 받을 때까지 걸린 초 */
    delaySec: number | null;
    status: DispatchStatus;
    attempts: number;
    detail: unknown;
  }>;
}

const FINISHED: DispatchStatus[] = ["sent", "failed", "skipped"];

export async function buildStatus(
  repo: Repo,
  nowSec: number,
  limits = { devices: 5, dispatches: 10 },
): Promise<StatusReport> {
  const [devices, candidates, places, dispatches] = await Promise.all([
    repo.listRecentDevices(limits.devices),
    repo.listSummaryCandidates(),
    repo.listActivePlaces(),
    repo.listRecentDispatches(limits.dispatches),
  ]);

  const users = new Map<string, StatusReport["users"][number]>();
  const entry = (userId: string) => {
    let u = users.get(userId);
    if (!u) users.set(userId, u = { user: short(userId), places: [], summary: null });
    return u;
  };
  for (const p of places) {
    if (p.userId !== null) entry(p.userId).places.push(p.kind);
  }
  for (const s of candidates) {
    entry(s.userId).summary = { time: s.summaryTime, tz: s.tz, threshold: s.threshold };
  }

  return {
    now: nowSec,
    devices: devices.map((d) => ({
      device: short(d.id),
      user: short(d.userId),
      env: d.apnsEnv,
      pushToStart: d.hasPushToStart,
      appVersion: d.appVersion,
      active: d.active,
      deactivatedReason: d.deactivatedReason,
      lastSeenAt: d.lastSeenAt,
    })),
    users: [...users.values()].map((u) => ({ ...u, places: u.places.sort() })),
    dispatches: dispatches.map((d) => {
      const finished = FINISHED.includes(d.status);
      return {
        user: short(d.userId),
        localDate: d.localDate,
        scheduledAt: d.scheduledAt,
        finishedAt: finished ? d.updatedAt : null,
        delaySec: d.status === "sent" ? d.updatedAt - d.scheduledAt : null,
        status: d.status,
        attempts: d.attempts,
        detail: d.detail,
      };
    }),
  };
}
