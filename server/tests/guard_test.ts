import { assertEquals } from "@std/assert";
import { checkSpikeToken } from "../supabase/functions/_shared/guard.ts";

const req = (token?: string) =>
  new Request("http://localhost/", { headers: token ? { "x-spike-token": token } : {} });

Deno.test("rejects when secret is not configured", () => {
  assertEquals(checkSpikeToken(req("x"), undefined)?.status, 503);
});

Deno.test("rejects missing or wrong token", () => {
  assertEquals(checkSpikeToken(req(), "secret")?.status, 401);
  assertEquals(checkSpikeToken(req("secreT"), "secret")?.status, 401);
  assertEquals(checkSpikeToken(req("secret-longer"), "secret")?.status, 401);
});

Deno.test("accepts matching token", () => {
  assertEquals(checkSpikeToken(req("secret"), "secret"), null);
});
