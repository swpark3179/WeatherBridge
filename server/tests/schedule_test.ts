import { assertEquals, assertThrows } from "@std/assert";
import {
  addDays,
  dueSummary,
  localDateOf,
  parseClock,
  zonedEpoch,
} from "../supabase/functions/_shared/schedule.ts";
import { kst } from "./fixtures.ts";

const SEOUL = { tz: "Asia/Seoul", summaryTime: "07:00" };

Deno.test("zonedEpoch converts Seoul wall clock to epoch", () => {
  assertEquals(
    zonedEpoch({ year: 2026, month: 10, day: 20 }, 7, 0, "Asia/Seoul"),
    kst(2026, 10, 20, 7),
  );
  assertEquals(localDateOf(kst(2026, 10, 20, 0, 30), "Asia/Seoul"), {
    year: 2026,
    month: 10,
    day: 20,
  });
});

Deno.test("summary is due from the scheduled minute for 15 minutes", () => {
  assertEquals(dueSummary(kst(2026, 10, 20, 6, 59), SEOUL), null);
  assertEquals(dueSummary(kst(2026, 10, 20, 7, 0), SEOUL), {
    localDate: "2026-10-20",
    scheduledAt: kst(2026, 10, 20, 7),
  });
  assertEquals(dueSummary(kst(2026, 10, 20, 7, 14), SEOUL)?.localDate, "2026-10-20");
  assertEquals(dueSummary(kst(2026, 10, 20, 7, 15), SEOUL), null);
});

Deno.test("a 23:55 summary still belongs to the previous day after midnight", () => {
  const late = { tz: "Asia/Seoul", summaryTime: "23:55:00" };
  assertEquals(dueSummary(kst(2026, 10, 21, 0, 5), late), {
    localDate: "2026-10-20",
    scheduledAt: kst(2026, 10, 20, 23, 55),
  });
});

Deno.test("DST: a missing wall time moves forward, a repeated one uses the first", () => {
  const ny = "America/New_York";
  // 2026-03-08 02:00 EST → 03:00 EDT, 02:30은 없다 → 03:30 EDT(07:30Z)
  assertEquals(
    zonedEpoch({ year: 2026, month: 3, day: 8 }, 2, 30, ny),
    Date.UTC(2026, 2, 8, 7, 30) / 1000,
  );
  // 2026-11-01 01:30은 두 번(EDT, EST) → 앞의 것(05:30Z)
  assertEquals(
    zonedEpoch({ year: 2026, month: 11, day: 1 }, 1, 30, ny),
    Date.UTC(2026, 10, 1, 5, 30) / 1000,
  );
  // 평소 날은 그대로 (07:00 EST = 12:00Z)
  assertEquals(
    zonedEpoch({ year: 2026, month: 1, day: 15 }, 7, 0, ny),
    Date.UTC(2026, 0, 15, 12) / 1000,
  );
});

Deno.test("addDays crosses month and year boundaries", () => {
  assertEquals(addDays({ year: 2026, month: 1, day: 1 }, -1), { year: 2025, month: 12, day: 31 });
  assertEquals(addDays({ year: 2026, month: 2, day: 28 }, 1), { year: 2026, month: 3, day: 1 });
});

Deno.test("parseClock accepts Postgres time strings and rejects junk", () => {
  assertEquals(parseClock("07:05:00"), { hour: 7, minute: 5 });
  assertEquals(parseClock("7:05"), { hour: 7, minute: 5 });
  assertThrows(() => parseClock("25:00"));
  assertThrows(() => parseClock("soon"));
});

Deno.test("an unknown time zone throws so dispatch can report it", () => {
  assertThrows(() =>
    dueSummary(kst(2026, 10, 20, 7), { tz: "Mars/Olympus", summaryTime: "07:00" })
  );
});
