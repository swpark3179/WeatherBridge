/**
 * 요약 알림 발송. pg_cron이 매분 dispatch 함수를 부르면, 예정 시각이 된 사용자에게 하루 한 번 보낸다.
 * - 보내기 전에 dispatch_log에 먼저 기록해(claim) 중복 발송을 막는다.
 * - 일시적인 실패(429, 5xx, 네트워크)는 예정 시각부터 15분 안에서 최대 3번까지 다시 시도한다.
 */
import { type ApnsKey, type FetchFn, sendToDevice, SharedProviderToken } from "./apns.ts";
import type { Briefing } from "./briefing.ts";
import type { Device, Repo, UserSettings } from "./db.ts";
import type { Deps } from "./forecast_service.ts";
import { dueSummary } from "./schedule.ts";
import { DEFAULT_THRESHOLD, loadForecasts, userBriefing } from "./today.ts";

export const MAX_ATTEMPTS = 3;

export interface ApnsConfig {
  key: ApnsKey;
  bundleId: string;
}

export interface DispatchOptions {
  /** 없으면 아무것도 보내지 않고 오류로 알린다 */
  apns: ApnsConfig | null;
  /** 기록·발송 없이 대상과 문구만 확인 */
  dryRun?: boolean;
  /** 이 사용자만. dryRun이면 예정 시각과 상관없이 문구를 만들어 본다. */
  userId?: string;
  /** APNs 호출용 (테스트에서 바꿔 끼움) */
  apnsFetch?: FetchFn;
}

export interface DeviceResult {
  device: string;
  status: number;
  reason?: string;
}

export interface DispatchReport {
  dryRun: boolean;
  /** 요약 알림을 켠 사용자 수 */
  candidates: number;
  /** 지금 예정 시각 구간에 든 사용자 수 */
  due: number;
  sent: number;
  retry: number;
  failed: number;
  skipped: number;
  errors: string[];
  /** dryRun일 때 만들어 본 알림 */
  previews: Array<{ user: string; localDate: string | null; payload: unknown }>;
}

/** 사용자 ID 앞 8자리만 로그·응답에 남긴다 */
const short = (id: string) => id.slice(0, 8);

export function summaryPayload(briefing: Briefing, localDate: string) {
  return {
    aps: {
      alert: {
        title: briefing.state.highlight ? "☔ 오늘 비 소식이 있어요" : "오늘은 비 소식이 없어요",
        body: briefing.summary,
      },
      sound: "default",
      "thread-id": "summary",
    },
    kind: "summary",
    localDate,
  };
}

/** 사용자 한 명의 오늘 요약 알림 (예보는 캐시 우선) */
async function buildPayload(
  deps: Deps,
  settings: UserSettings | null,
  userId: string,
  nowSec: number,
  localDate: string,
) {
  const places = await deps.repo.listUserPlaces(userId);
  if (places.length === 0) return null;
  const loaded = await loadForecasts(deps, places);
  const briefing = userBriefing(loaded, {
    nowSec,
    tz: settings?.tz ?? places[0].tz,
    threshold: settings?.threshold ?? DEFAULT_THRESHOLD,
  });
  return {
    payload: summaryPayload(briefing, localDate),
    errors: loaded.flatMap((l) => l.errors.map((e) => `${l.place.kind}: ${e}`)),
  };
}

type Outcome = "sent" | "retryable" | "permanent";

async function sendToDevices(
  repo: Repo,
  tokens: SharedProviderToken,
  apns: ApnsConfig,
  devices: Device[],
  payload: unknown,
  opts: { nowSec: number; collapseId: string; fetchFn?: FetchFn },
): Promise<{ outcomes: Outcome[]; results: DeviceResult[] }> {
  const outcomes: Outcome[] = [];
  const results: DeviceResult[] = [];
  for (const device of devices) {
    const send = (providerToken: string) =>
      sendToDevice({
        env: device.apnsEnv,
        providerToken,
        deviceToken: device.apnsToken,
        topic: apns.bundleId,
        pushType: "alert",
        priority: 10,
        payload,
        // 1시간 안에 전달되지 않으면 버린다(오래된 요약은 의미가 없다)
        expiration: opts.nowSec + 3600,
        collapseId: opts.collapseId,
      }, opts.fetchFn);
    try {
      let res = await send(await tokens.get(opts.nowSec));
      if (res.status === 403 && reasonOf(res.body) === "ExpiredProviderToken") {
        res = await send(await tokens.renew(opts.nowSec));
      }
      const reason = reasonOf(res.body);
      results.push({ device: device.id.slice(0, 8), status: res.status, reason });
      if (res.status === 200) {
        outcomes.push("sent");
      } else if (res.status === 410) {
        // 앱 삭제 등으로 더 이상 유효하지 않은 토큰
        await repo.deactivateDevice(device.id, `410 ${reason ?? "Unregistered"}`);
        outcomes.push("permanent");
      } else if (res.status === 429 || res.status >= 500) {
        outcomes.push("retryable");
      } else {
        // 400 BadDeviceToken은 대개 환경(sandbox/production)이 맞지 않는 경우라 지우지 않고 기록만 한다
        outcomes.push("permanent");
      }
    } catch (e) {
      results.push({ device: device.id.slice(0, 8), status: 0, reason: String(e) });
      outcomes.push("retryable");
    }
  }
  return { outcomes, results };
}

export async function runDispatch(deps: Deps, opts: DispatchOptions): Promise<DispatchReport> {
  const nowSec = Math.floor(deps.nowMs() / 1000);
  const report: DispatchReport = {
    dryRun: opts.dryRun ?? false,
    candidates: 0,
    due: 0,
    sent: 0,
    retry: 0,
    failed: 0,
    skipped: 0,
    errors: [],
    previews: [],
  };

  let candidates = await deps.repo.listSummaryCandidates();
  if (opts.userId) candidates = candidates.filter((c) => c.userId === opts.userId);
  report.candidates = candidates.length;

  if (report.dryRun) {
    for (const s of candidates) {
      try {
        const due = dueSummary(nowSec, s);
        if (due) report.due++;
        if (opts.userId) {
          const built = await buildPayload(deps, s, s.userId, nowSec, due?.localDate ?? "dry-run");
          report.previews.push({
            user: short(s.userId),
            localDate: due?.localDate ?? null,
            payload: built?.payload ?? null,
          });
        }
      } catch (e) {
        report.errors.push(`${short(s.userId)}: ${e}`);
      }
    }
    // 요약 알림을 켜지 않은 사용자라도 문구는 만들어 볼 수 있게 한다(점검용)
    if (opts.userId && candidates.length === 0) {
      const settings = await deps.repo.getUserSettings(opts.userId);
      const built = await buildPayload(deps, settings, opts.userId, nowSec, "dry-run");
      report.previews.push({
        user: short(opts.userId),
        localDate: null,
        payload: built?.payload ?? null,
      });
    }
    return report;
  }

  const due = candidates.flatMap((s) => {
    try {
      const slot = dueSummary(nowSec, s);
      return slot ? [{ settings: s, slot }] : [];
    } catch (e) {
      report.errors.push(`${short(s.userId)}: ${e}`);
      return [];
    }
  });
  report.due = due.length;
  if (due.length === 0) return report;
  if (!opts.apns) {
    report.errors.push("APNs 시크릿(APNS_TEAM_ID·APNS_KEY_ID·APNS_P8)이 없어 보내지 않았습니다");
    return report;
  }
  const tokens = new SharedProviderToken(deps.repo, opts.apns.key);

  for (const { settings, slot } of due) {
    const claim = await deps.repo.claimDispatch(
      {
        userId: settings.userId,
        kind: "summary",
        localDate: slot.localDate,
        scheduledAt: slot.scheduledAt,
      },
      MAX_ATTEMPTS,
    );
    if (!claim) continue; // 이미 보냈거나 다른 실행이 처리 중

    try {
      const devices = await deps.repo.listActiveDevices(settings.userId);
      const built = devices.length
        ? await buildPayload(deps, settings, settings.userId, nowSec, slot.localDate)
        : null;
      if (!built) {
        await deps.repo.finishDispatch(claim.id, "skipped", {
          reason: devices.length ? "no_places" : "no_devices",
        });
        report.skipped++;
        continue;
      }
      const { outcomes, results } = await sendToDevices(
        deps.repo,
        tokens,
        opts.apns,
        devices,
        built.payload,
        {
          nowSec,
          collapseId: `summary-${slot.localDate}`,
          fetchFn: opts.apnsFetch,
        },
      );
      const status = outcomes.includes("sent")
        ? "sent"
        : outcomes.includes("retryable") && claim.attempts < MAX_ATTEMPTS
        ? "retry"
        : "failed";
      await deps.repo.finishDispatch(claim.id, status, {
        results,
        forecastErrors: built.errors,
      });
      report[status]++;
    } catch (e) {
      const status = claim.attempts < MAX_ATTEMPTS ? "retry" : "failed";
      await deps.repo.finishDispatch(claim.id, status, { error: String(e) });
      report[status]++;
      report.errors.push(`${short(settings.userId)}: ${e}`);
    }
  }
  return report;
}

function reasonOf(body: unknown): string | undefined {
  return typeof body === "object" && body !== null && "reason" in body
    ? String((body as { reason: unknown }).reason)
    : undefined;
}
