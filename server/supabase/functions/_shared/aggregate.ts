/**
 * 여러 예보의 시간별 강수확률 종합 (docs/IMPLEMENTATION_PLAN.md "강수확률 종합 알고리즘").
 * - 1시간 해상도 값만 시간별 종합에 쓴다(3시간 구간 확률은 제외).
 * - 같은 계열은 평균 내어 한 표로, 계열 간에는 가중 평균(국내 기상청 1.5).
 */
import type { Family, ProviderForecast, ProviderId } from "./forecast_types.ts";

/** 등급 경계는 ios/Packages/WeatherCore RainLevel과 같다. */
export type RainLevel = "clear" | "low" | "moderate" | "high";

export function rainLevel(pop: number): RainLevel {
  if (pop < 20) return "clear";
  if (pop < 40) return "low";
  if (pop < 60) return "moderate";
  return "high";
}

export const FAMILY_WEIGHTS: Record<Family, number> = { kma: 1.5, ecmwf: 1, ncep: 1, dwd: 1 };
/** 한 소스라도 이 이상이면 "강하게 비 예보"로 본다 */
const STRONG_POP = 60;
/** 계열 간 차이가 이 이상이면 "의견 갈림" */
const SPLIT_SPREAD = 40;

export interface HourAgg {
  t: number;
  /** 계열 가중 평균 (반올림 %) */
  consensus: number | null;
  min: number | null;
  max: number | null;
  level: RainLevel | null;
  /** 계열별 값 */
  families: Partial<Record<Family, number>>;
  /** 소스별 값 (한 계열에 소스가 여럿이면 계열 값은 이들의 평균) */
  providers: Partial<Record<ProviderId, number>>;
  /** 임계값 이상인 계열 수 / 참여 계열 수 */
  agreeing: number;
  total: number;
  /** 소스 간 차이가 큼 */
  split: boolean;
  /** 강조 대상 시간 */
  rainy: boolean;
  /** 직전 시간과 참여 계열 구성이 다름 (예보 범위 경계) */
  bandChange: boolean;
  /** 기온 (기상청 우선) */
  temp: number | null;
}

export interface RainWindow {
  start: number;
  /** 끝 시각 (포함하지 않음) */
  end: number;
  maxPop: number;
  agreeing: number;
  total: number;
}

export interface Aggregate {
  hours: HourAgg[];
  windows: RainWindow[];
  maxPop: number;
  highlight: boolean;
}

/** 하루(또는 남은 하루) 종합. 시간대 없이 그 날 비가 오는지만 본다. */
export interface DayAgg {
  /** 계열마다 그 날 가장 높은 강수확률을 가중 평균한 값. 쓸 예보가 없으면 null */
  pop: number | null;
  /** 그 날 최고값이 임계값 이상인 계열 수 / 참여 계열 수 */
  agreeing: number;
  total: number;
  rainy: boolean;
}

const TEMP_PRIORITY: Family[] = ["kma", "ecmwf", "dwd", "ncep"];

/** 종합 확률이 임계값 이상이거나, 기상청 또는 두 계열 이상이 강하게 비를 예보 */
function isRainy(
  consensus: number,
  families: Partial<Record<Family, number>>,
  threshold: number,
): boolean {
  const strong = Object.values(families).filter((v) => v >= STRONG_POP).length;
  return consensus >= threshold || (families.kma ?? 0) >= STRONG_POP || strong >= 2;
}

function weightedConsensus(entries: [Family, number][]): number {
  const weightSum = entries.reduce((a, [f]) => a + FAMILY_WEIGHTS[f], 0);
  return Math.round(entries.reduce((a, [f, v]) => a + v * FAMILY_WEIGHTS[f], 0) / weightSum);
}

/**
 * [from, to) 하루 종합: 계열마다 그 날 최고 강수확률을 구해 계열 간 가중 평균한다.
 * 예보끼리 비 오는 시각이 어긋나도 "그 날 비"가 희석되지 않는다(시간별 종합의 최고값보다 높을 수 있다).
 * - 구간 끝(to)까지 닿는 예보만 쓴다. 중간에 끝나는 예보의 반나절 최고값은 그 날 값이 아니다.
 * - 기상청 연장구간(3시간 구간 확률)도 쓴다. 구간 확률은 구간·하루 단위 종합에는 쓸 수 있다.
 */
export function aggregateDay(
  forecasts: ProviderForecast[],
  opts: { from: number; to: number; threshold?: number },
): DayAgg {
  const threshold = opts.threshold ?? 30;
  const maxByFamily = new Map<Family, number[]>();
  for (const f of forecasts) {
    const known = f.slots.filter((s) => s.pop !== null);
    const reach = Math.max(-Infinity, ...known.map((s) => s.t + s.span * 3600));
    if (reach < opts.to) continue;
    const pops = known.filter((s) => s.t >= opts.from && s.t < opts.to).map((s) => s.pop!);
    if (pops.length === 0) continue;
    maxByFamily.set(f.family, [...(maxByFamily.get(f.family) ?? []), Math.max(...pops)]);
  }

  const families: Partial<Record<Family, number>> = {};
  for (const [family, values] of maxByFamily) {
    families[family] = Math.round(values.reduce((a, b) => a + b, 0) / values.length);
  }
  const entries = Object.entries(families) as [Family, number][];
  if (entries.length === 0) return { pop: null, agreeing: 0, total: 0, rainy: false };

  const pop = weightedConsensus(entries);
  return {
    pop,
    agreeing: entries.filter(([, v]) => v >= threshold).length,
    total: entries.length,
    rainy: isRainy(pop, families, threshold),
  };
}

export function aggregate(
  forecasts: ProviderForecast[],
  opts: { from: number; to: number; threshold?: number },
): Aggregate {
  const threshold = opts.threshold ?? 30;
  const popByFamily = new Map<number, Map<Family, number[]>>();
  const popByProvider = new Map<number, Partial<Record<ProviderId, number>>>();
  const tempByFamily = new Map<number, Map<Family, number>>();

  for (const f of forecasts) {
    for (const s of f.slots) {
      if (s.t < opts.from || s.t >= opts.to) continue;
      if (s.span === 1 && s.pop !== null) {
        const fam = popByFamily.get(s.t) ?? new Map<Family, number[]>();
        fam.set(f.family, [...(fam.get(f.family) ?? []), s.pop]);
        popByFamily.set(s.t, fam);
        popByProvider.set(s.t, { ...popByProvider.get(s.t), [f.provider]: s.pop });
      }
      if (s.temp !== null) {
        const temps = tempByFamily.get(s.t) ?? new Map<Family, number>();
        if (!temps.has(f.family)) temps.set(f.family, s.temp);
        tempByFamily.set(s.t, temps);
      }
    }
  }

  const hours: HourAgg[] = [];
  let prevSet = "";
  for (let t = Math.ceil(opts.from / 3600) * 3600; t < opts.to; t += 3600) {
    const fams = popByFamily.get(t);
    const families: Partial<Record<Family, number>> = {};
    for (const [family, values] of fams ?? []) {
      families[family] = Math.round(values.reduce((a, b) => a + b, 0) / values.length);
    }
    const entries = Object.entries(families) as [Family, number][];
    const set = entries.map(([f]) => f).sort().join(",");
    const temps = tempByFamily.get(t);
    const temp = TEMP_PRIORITY.map((f) => temps?.get(f)).find((v) => v !== undefined) ?? null;
    const providers = popByProvider.get(t) ?? {};

    if (entries.length === 0) {
      hours.push({
        t,
        consensus: null,
        min: null,
        max: null,
        level: null,
        families,
        providers,
        agreeing: 0,
        total: 0,
        split: false,
        rainy: false,
        bandChange: hours.length > 0 && set !== prevSet,
        temp,
      });
      prevSet = set;
      continue;
    }

    const consensus = weightedConsensus(entries);
    const values = entries.map(([, v]) => v);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const rainy = isRainy(consensus, families, threshold);

    hours.push({
      t,
      consensus,
      min,
      max,
      level: rainLevel(consensus),
      families,
      providers,
      agreeing: values.filter((v) => v >= threshold).length,
      total: entries.length,
      split: max - min >= SPLIT_SPREAD,
      rainy,
      bandChange: hours.length > 0 && set !== prevSet,
      temp,
    });
    prevSet = set;
  }

  const windows: RainWindow[] = [];
  for (const h of hours) {
    if (!h.rainy || h.consensus === null) continue;
    const last = windows.at(-1);
    if (last && last.end === h.t) {
      last.end = h.t + 3600;
      if (h.consensus > last.maxPop) {
        Object.assign(last, { maxPop: h.consensus, agreeing: h.agreeing, total: h.total });
      }
    } else {
      windows.push({
        start: h.t,
        end: h.t + 3600,
        maxPop: h.consensus,
        agreeing: h.agreeing,
        total: h.total,
      });
    }
  }

  return {
    hours,
    windows,
    maxPop: Math.max(0, ...hours.map((h) => h.consensus ?? 0)),
    highlight: windows.length > 0,
  };
}
