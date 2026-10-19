/**
 * 집·회사 오늘 브리핑. 출력은 Live Activity 계약(CommuteState)과 같은 형식이라
 * Phase 2 요약 알림과 Phase 3 잠금화면에서 그대로 쓴다.
 */
import type { Aggregate, RainWindow } from "./aggregate.ts";
import type { CommuteState, PlaceBrief } from "./apns.ts";

export interface BriefingPlace {
  name: string;
  /** 오늘 남은 시간(현재 시각~자정)으로 계산한 종합 결과 */
  aggregate: Aggregate;
}

export interface Briefing {
  state: CommuteState;
  /** pops[0]의 현지 시각 */
  firstHour: number;
  /** 알림 본문용 한 줄 요약 */
  summary: string;
}

/** 현지 시각의 시(0–23) */
export function localHour(epochSec: number, tz: string): number {
  const h = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", hourCycle: "h23" })
    .format(new Date(epochSec * 1000));
  return Number(h);
}

/** 지금이 속한 시각부터 그 날 자정까지 [from, to) (epoch 초) */
export function restOfLocalDay(nowSec: number, tz: string): { from: number; to: number } {
  const from = Math.floor(nowSec / 3600) * 3600;
  const hoursLeft = 24 - localHour(from, tz);
  return { from, to: from + hoursLeft * 3600 };
}

export function windowLabel(w: RainWindow, tz: string): string {
  const start = localHour(w.start, tz);
  const endHour = localHour(w.end, tz);
  const end = endHour === 0 ? 24 : endHour;
  return end - start <= 1 ? `${start}시` : `${start}–${end}시`;
}

export function buildBriefing(opts: {
  nowSec: number;
  tz: string;
  places: BriefingPlace[];
}): Briefing {
  const { from } = restOfLocalDay(opts.nowSec, opts.tz);
  const briefs: PlaceBrief[] = opts.places.map(({ name, aggregate }) => {
    const top = topWindow(aggregate.windows);
    return {
      name,
      temp: aggregate.hours[0]?.temp === null || aggregate.hours[0]?.temp === undefined
        ? null
        : Math.round(aggregate.hours[0].temp),
      pops: aggregate.hours.map((h) => h.consensus ?? 0),
      maxPop: aggregate.maxPop,
      rainWindow: top ? windowLabel(top, opts.tz) : null,
    };
  });

  const rainy = opts.places
    .map((p, i) => ({ name: p.name, top: topWindow(p.aggregate.windows), brief: briefs[i] }))
    .filter((p) => p.top !== null)
    .sort((a, b) => b.top!.maxPop - a.top!.maxPop);

  const highlight = rainy.length > 0;
  const headline = highlight
    ? "☔ " + rainy.map((p) => `${p.name} ${p.brief.rainWindow} 최대 ${p.top!.maxPop}%`).join(" · ")
    : `오늘 비 소식 없음 (최대 ${Math.max(0, ...briefs.map((b) => b.maxPop))}%)`;
  const summary = briefs
    .map((b) =>
      b.rainWindow
        ? `${b.name} ☔ ${b.rainWindow} 최대 ${b.maxPop}%`
        : `${b.name} 비 소식 없음(최대 ${b.maxPop}%)`
    )
    .join(" / ");

  return {
    state: { headline, highlight, places: briefs, updatedAt: opts.nowSec },
    firstHour: localHour(from, opts.tz),
    summary,
  };
}

function topWindow(windows: RainWindow[]): RainWindow | null {
  return windows.reduce<RainWindow | null>((a, w) => (!a || w.maxPop > a.maxPop ? w : a), null);
}
