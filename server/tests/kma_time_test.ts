import { assertEquals } from "@std/assert";
import { latestVilageBase } from "../supabase/functions/_shared/kma_time.ts";

/** KST 시각을 epoch ms로 */
function kst(y: number, mo: number, d: number, h: number, mi: number): number {
  return Date.UTC(y, mo - 1, d, h - 9, mi);
}

Deno.test("before first publish of the day uses previous day 23:00", () => {
  assertEquals(latestVilageBase(kst(2026, 10, 19, 2, 9)), {
    baseDate: "20261018",
    baseTime: "2300",
  });
  assertEquals(latestVilageBase(kst(2026, 10, 19, 0, 30)), {
    baseDate: "20261018",
    baseTime: "2300",
  });
});

Deno.test("waits 15 minutes after each publish", () => {
  assertEquals(latestVilageBase(kst(2026, 10, 19, 2, 14)), {
    baseDate: "20261018",
    baseTime: "2300",
  });
  assertEquals(latestVilageBase(kst(2026, 10, 19, 2, 15)), {
    baseDate: "20261019",
    baseTime: "0200",
  });
  assertEquals(latestVilageBase(kst(2026, 10, 19, 7, 59)), {
    baseDate: "20261019",
    baseTime: "0500",
  });
  assertEquals(latestVilageBase(kst(2026, 10, 19, 23, 59)), {
    baseDate: "20261019",
    baseTime: "2300",
  });
});

Deno.test("rolls over month and year boundaries", () => {
  assertEquals(latestVilageBase(kst(2027, 1, 1, 1, 0)), { baseDate: "20261231", baseTime: "2300" });
  assertEquals(latestVilageBase(kst(2026, 11, 1, 2, 0)), {
    baseDate: "20261031",
    baseTime: "2300",
  });
});

Deno.test("custom delay", () => {
  assertEquals(latestVilageBase(kst(2026, 10, 19, 5, 10), 10), {
    baseDate: "20261019",
    baseTime: "0500",
  });
});
