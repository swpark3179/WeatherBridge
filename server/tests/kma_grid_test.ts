import { assert, assertEquals } from "@std/assert";
import { isKmaCovered, kmaLocKey, toKmaGrid } from "../supabase/functions/_shared/kma_grid.ts";

Deno.test("converts city halls to KMA published grid points", () => {
  assertEquals(toKmaGrid(37.5665, 126.978), { nx: 60, ny: 127 }); // 서울
  assertEquals(toKmaGrid(35.1796, 129.0756), { nx: 98, ny: 76 }); // 부산
  assertEquals(toKmaGrid(37.4563, 126.7052), { nx: 55, ny: 124 }); // 인천
  assertEquals(toKmaGrid(35.1601, 126.8514), { nx: 58, ny: 74 }); // 광주
  assertEquals(toKmaGrid(36.3504, 127.3845), { nx: 67, ny: 100 }); // 대전
});

Deno.test("nearby points share a 5km cell", () => {
  assertEquals(toKmaGrid(37.5799, 126.9894), toKmaGrid(37.5665, 126.978));
});

Deno.test("coverage excludes overseas locations", () => {
  assert(isKmaCovered(33.4996, 126.5312)); // 제주
  assert(!isKmaCovered(35.6762, 139.6503)); // 도쿄
  assert(!isKmaCovered(48.8566, 2.3522)); // 파리
});

Deno.test("loc key format", () => {
  assertEquals(kmaLocKey({ nx: 60, ny: 127 }), "kma:60:127");
});
