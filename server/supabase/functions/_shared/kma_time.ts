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

function ymd(d: Date): string {
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${d.getUTCFullYear()}${m}${day}`;
}

function hh00(hour: number): string {
  return `${String(hour).padStart(2, "0")}00`;
}
