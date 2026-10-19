/**
 * 사용자 현지 시각 계산. 요약 알림의 예정 시각과 "하루 한 번"의 기준 날짜(local_date)에 쓴다.
 * 시간대는 IANA 이름(예: Asia/Seoul)이며, 서머타임이 있는 곳도 처리한다.
 */

export interface LocalDate {
  year: number;
  month: number;
  day: number;
}

/** 요약 알림을 예정 시각부터 이 시간 안에 보낸다. 그 사이 실패하면 매분 다시 시도한다. */
export const SUMMARY_WINDOW_SEC = 15 * 60;

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(tz: string): Intl.DateTimeFormat {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    formatters.set(tz, f);
  }
  return f;
}

/** epoch 초의 현지 날짜·시각. 잘못된 시간대면 RangeError. */
export function zonedParts(epochSec: number, tz: string) {
  const parts = Object.fromEntries(
    formatter(tz).formatToParts(new Date(epochSec * 1000)).map((p) => [p.type, p.value]),
  );
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
  };
}

export function formatLocalDate(d: LocalDate): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.year}-${p(d.month)}-${p(d.day)}`;
}

export function localDateOf(epochSec: number, tz: string): LocalDate {
  const { year, month, day } = zonedParts(epochSec, tz);
  return { year, month, day };
}

export function addDays(d: LocalDate, days: number): LocalDate {
  const t = new Date(Date.UTC(d.year, d.month - 1, d.day + days));
  return { year: t.getUTCFullYear(), month: t.getUTCMonth() + 1, day: t.getUTCDate() };
}

/** 현지 시각과 UTC의 차이(초). 서울은 +32400. */
function offsetAt(epochSec: number, tz: string): number {
  const p = zonedParts(epochSec, tz);
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) / 1000 - epochSec;
}

/**
 * 현지 날짜·시각 → epoch 초.
 * 서머타임 시작으로 그 시각이 없으면 뒤로 민다(02:30 → 03:30). 두 번 있으면 앞의 것.
 */
export function zonedEpoch(date: LocalDate, hour: number, minute: number, tz: string): number {
  const wall = Date.UTC(date.year, date.month - 1, date.day, hour, minute) / 1000;
  const first = wall - offsetAt(wall, tz);
  const second = wall - offsetAt(first, tz);
  if (second + offsetAt(second, tz) === wall) return second;
  if (first + offsetAt(first, tz) === wall) return first;
  return Math.max(first, second);
}

/** "HH:MM" 또는 "HH:MM:SS" */
export function parseClock(value: string): { hour: number; minute: number } {
  const m = /^(\d{1,2}):(\d{2})/.exec(value);
  if (!m) throw new Error(`시각 형식이 아닙니다: ${value}`);
  const hour = Number(m[1]);
  const minute = Number(m[2]);
  if (hour > 23 || minute > 59) throw new Error(`시각 범위를 벗어났습니다: ${value}`);
  return { hour, minute };
}

export interface DueSlot {
  /** 현지 날짜 "YYYY-MM-DD" (하루 한 번 보장의 기준) */
  localDate: string;
  /** 예정 시각 (epoch 초) */
  scheduledAt: number;
}

/**
 * 지금 보내야 하는 요약 알림. 예정 시각부터 windowSec 동안만 대상이다.
 * 오늘 것과 어제 것을 함께 본다(23:55 예정이 자정을 넘겨 재시도되는 경우).
 */
export function dueSummary(
  nowSec: number,
  settings: { tz: string; summaryTime: string },
  windowSec = SUMMARY_WINDOW_SEC,
): DueSlot | null {
  const { hour, minute } = parseClock(settings.summaryTime);
  const today = localDateOf(nowSec, settings.tz);
  for (const date of [today, addDays(today, -1)]) {
    const at = zonedEpoch(date, hour, minute, settings.tz);
    if (nowSec >= at && nowSec < at + windowSec) {
      return { localDate: formatLocalDate(date), scheduledAt: at };
    }
  }
  return null;
}
