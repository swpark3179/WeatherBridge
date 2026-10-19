import { assertEquals } from "@std/assert";
import {
  kstToEpoch,
  latestUltraSrtNcstBase,
  latestVilageBase,
  nextVilageAvailableAt,
} from "../supabase/functions/_shared/kma_time.ts";

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

Deno.test("next vilage forecast becomes available 3 hours later (+15m)", () => {
  const issued = kst(2026, 10, 19, 5, 0) / 1000;
  assertEquals(
    nextVilageAvailableAt({ baseDate: "20261019", baseTime: "0500" }),
    issued + 3 * 3600 + 15 * 60,
  );
  // 23시 발표 다음은 이튿날 02시
  assertEquals(
    nextVilageAvailableAt({ baseDate: "20261019", baseTime: "2300" }),
    kst(2026, 10, 20, 2, 15) / 1000,
  );
});

Deno.test("ultra short observation uses the hour that is 40 minutes old", () => {
  assertEquals(latestUltraSrtNcstBase(kst(2026, 10, 19, 7, 20)), {
    baseDate: "20261019",
    baseTime: "0600",
  });
  assertEquals(latestUltraSrtNcstBase(kst(2026, 10, 19, 7, 45)), {
    baseDate: "20261019",
    baseTime: "0700",
  });
  assertEquals(latestUltraSrtNcstBase(kst(2026, 10, 19, 0, 10)), {
    baseDate: "20261018",
    baseTime: "2300",
  });
});

Deno.test("kstToEpoch", () => {
  assertEquals(kstToEpoch("20261019", "0600"), kst(2026, 10, 19, 6, 0) / 1000);
});
