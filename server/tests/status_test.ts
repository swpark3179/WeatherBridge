import { assert, assertEquals } from "@std/assert";
import { MemoryRepo, type Place } from "../supabase/functions/_shared/db.ts";
import { buildStatus } from "../supabase/functions/_shared/status.ts";
import { kst } from "./fixtures.ts";

const A = "aaaaaaaa-1111-2222-3333-000000000001";
const B = "bbbbbbbb-1111-2222-3333-000000000002";
const APNS = "ab".repeat(32);
const PUSH_TO_START = "cd".repeat(40);

function place(id: string, userId: string | null, kind: "home" | "office"): Place {
  return {
    id,
    userId,
    kind,
    name: kind === "home" ? "집" : "회사",
    lat: 37.57,
    lon: 126.98,
    tz: "Asia/Seoul",
    kmaNx: 60,
    kmaNy: 127,
  };
}

function setup() {
  const repo = new MemoryRepo();
  const at = kst(2026, 10, 21, 7);
  repo.places = [
    place("p1", A, "office"),
    place("p2", A, "home"),
    place("p3", B, "home"),
    place("op", null, "home"),
  ];
  repo.settings = [
    { userId: A, tz: "Asia/Seoul", summaryEnabled: true, summaryTime: "07:00", threshold: 30 },
    { userId: B, tz: "Asia/Seoul", summaryEnabled: false, summaryTime: "08:00", threshold: 30 },
  ];
  repo.devices = [
    {
      id: "dev-old-0000",
      userId: A,
      apnsToken: "ef".repeat(32),
      apnsEnv: "production",
      active: false,
      reason: "410 Unregistered",
      lastSeenAt: at - 7200,
    },
    {
      id: "dev-new-0000",
      userId: A,
      apnsToken: APNS,
      apnsEnv: "production",
      active: true,
      reason: null,
      pushToStartToken: PUSH_TO_START,
      appVersion: "0.1.0 (5.1)",
      lastSeenAt: at - 60,
    },
  ];
  repo.dispatches = [
    {
      id: 1,
      userId: A,
      kind: "summary",
      localDate: "2026-10-20",
      scheduledAt: at - 86400,
      status: "retry",
      attempts: 1,
      detail: { results: [{ device: "dev-new-", status: 503 }] },
      updatedAt: at - 86400 + 5,
    },
    {
      id: 2,
      userId: A,
      kind: "summary",
      localDate: "2026-10-21",
      scheduledAt: at,
      status: "sent",
      attempts: 1,
      detail: { results: [{ device: "dev-new-", status: 200 }] },
      updatedAt: at + 7,
    },
  ];
  return { repo, at };
}

Deno.test("status reports devices, users and dispatch delay without tokens or coordinates", async () => {
  const { repo, at } = setup();
  const report = await buildStatus(repo, at + 30);

  assertEquals(report.devices.map((d) => [d.device, d.active, d.pushToStart]), [
    ["dev-new-", true, true],
    ["dev-old-", false, false],
  ]);
  assertEquals(report.devices[0].appVersion, "0.1.0 (5.1)");
  assertEquals(report.devices[1].deactivatedReason, "410 Unregistered");

  // 운영 장소(user_id 없음)는 빼고, 요약 알림을 끈 사용자는 summary가 null
  assertEquals(report.users, [
    {
      user: "aaaaaaaa",
      places: ["home", "office"],
      summary: { time: "07:00", tz: "Asia/Seoul", threshold: 30 },
    },
    { user: "bbbbbbbb", places: ["home"], summary: null },
  ]);

  assertEquals(report.dispatches.map((d) => [d.localDate, d.status, d.delaySec, d.finishedAt]), [
    ["2026-10-21", "sent", 7, at + 7],
    ["2026-10-20", "retry", null, null],
  ]);

  const text = JSON.stringify(report);
  for (const secret of [APNS, PUSH_TO_START, "37.57", "126.98", A, B]) {
    assert(!text.includes(secret), `응답에 ${secret.slice(0, 8)}…이 들어 있다`);
  }
});

Deno.test("latest device is the most recently seen active one in that environment", async () => {
  const { repo } = setup();
  assertEquals(await repo.latestDevice("production"), {
    id: "dev-new-0000",
    apnsToken: APNS,
    pushToStartToken: PUSH_TO_START,
  });
  assertEquals(await repo.latestDevice("sandbox"), null);

  repo.devices[1].active = false;
  assertEquals(await repo.latestDevice("production"), null);
});

Deno.test("status limits the number of rows", async () => {
  const { repo, at } = setup();
  const report = await buildStatus(repo, at, { devices: 1, dispatches: 1 });
  assertEquals(report.devices.length, 1);
  assertEquals(report.dispatches.map((d) => d.localDate), ["2026-10-21"]);
});
