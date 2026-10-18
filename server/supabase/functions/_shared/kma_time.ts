/** 기상청 단기예보(getVilageFcst) 발표 시각 (KST) */
export const VILAGE_BASE_HOURS = [2, 5, 8, 11, 14, 17, 20, 23] as const;

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

export interface KmaBase {
  baseDate: string; // YYYYMMDD
  baseTime: string; // HH00
}

/**
 * 지금 조회 가능한 가장 최근 단기예보 발표를 고른다.
 * 발표 후 API 반영까지 약 10분이 걸려 기본 15분을 기다린다. KST는 서머타임이 없어 +09:00 고정.
 */
export function latestVilageBase(nowMs: number, delayMinutes = 15): KmaBase {
  const kst = new Date(nowMs + KST_OFFSET_MS);
  const minutesOfDay = kst.getUTCHours() * 60 + kst.getUTCMinutes();
  const hour = [...VILAGE_BASE_HOURS].reverse().find((h) => h * 60 + delayMinutes <= minutesOfDay);
  if (hour !== undefined) {
    return { baseDate: ymd(kst), baseTime: hh00(hour) };
  }
  const prevDay = new Date(kst.getTime() - 24 * 60 * 60 * 1000);
  return { baseDate: ymd(prevDay), baseTime: hh00(23) };
}

/** 이 발표 다음 단기예보가 조회 가능해지는 시각(epoch 초). 캐시 만료 기준. */
export function nextVilageAvailableAt(base: KmaBase, delayMinutes = 15): number {
  const issued = kstToEpoch(base.baseDate, base.baseTime);
  const hour = Number(base.baseTime.slice(0, 2));
  const next = VILAGE_BASE_HOURS.find((h) => h > hour);
  const gapHours = next === undefined ? 24 - hour + VILAGE_BASE_HOURS[0] : next - hour;
  return issued + gapHours * 3600 + delayMinutes * 60;
}

/**
 * 지금 조회 가능한 가장 최근 초단기실황(getUltraSrtNcst). 매시 정각 관측이 약 40분 뒤 제공된다.
 */
export function latestUltraSrtNcstBase(nowMs: number, delayMinutes = 40): KmaBase {
  const kst = new Date(nowMs + KST_OFFSET_MS - delayMinutes * 60 * 1000);
  return { baseDate: ymd(kst), baseTime: hh00(kst.getUTCHours()) };
}

/** 기상청 날짜(YYYYMMDD)·시각(HHMM, KST) → epoch 초 */
export function kstToEpoch(yyyymmdd: string, hhmm: string): number {
  const ms = Date.UTC(
    Number(yyyymmdd.slice(0, 4)),
    Number(yyyymmdd.slice(4, 6)) - 1,
    Number(yyyymmdd.slice(6, 8)),
    Number(hhmm.slice(0, 2)),
    Number(hhmm.slice(2, 4)),
  );
  return (ms - KST_OFFSET_MS) / 1000;
}

function ymd(d: Date): string {
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${d.getUTCFullYear()}${m}${day}`;
}

function hh00(hour: number): string {
  return `${String(hour).padStart(2, "0")}00`;
}
