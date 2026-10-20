import { assert, assertEquals } from "@std/assert";
import { ascToken, pickProfile, profilesUrl } from "../scripts/asc_profiles.ts";

function b64urlJson(s: string): unknown {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return JSON.parse(atob(b64));
}

Deno.test("ASC token has App Store Connect claims and a 10 minute lifetime", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...pkcs8))
  }\n-----END PRIVATE KEY-----`;
  const jwt = await ascToken(
    { keyId: "KEY", issuerId: "ISSUER", privateKeyPem: pem },
    1_700_000_000,
  );
  const [h, c] = jwt.split(".");
  assertEquals(b64urlJson(h), { alg: "ES256", kid: "KEY", typ: "JWT" });
  assertEquals(b64urlJson(c), {
    iss: "ISSUER",
    iat: 1_700_000_000,
    exp: 1_700_000_600,
    aud: "appstoreconnect-v1",
  });
});

Deno.test("profiles URL filters by exact name", () => {
  const url = new URL(profilesUrl("WeatherBridge AppStore"));
  assertEquals(url.pathname, "/v1/profiles");
  assertEquals(url.searchParams.get("filter[name]"), "WeatherBridge AppStore");
  assert(url.searchParams.get("fields[profiles]")!.includes("profileContent"));
});

Deno.test("pickProfile keeps active App Store profiles with the same name, latest expiry first", () => {
  const p = (name: string, state: string, type: string, exp: string, uuid: string) => ({
    attributes: {
      name,
      profileState: state,
      profileType: type,
      expirationDate: exp,
      uuid,
      profileContent: "AAAA",
    },
  });
  const body = {
    data: [
      p("WeatherBridge AppStore", "ACTIVE", "IOS_APP_STORE", "2027-01-01T00:00:00Z", "old"),
      p("WeatherBridge AppStore", "ACTIVE", "IOS_APP_STORE", "2027-06-01T00:00:00Z", "new"),
      p("WeatherBridge AppStore", "INVALID", "IOS_APP_STORE", "2028-01-01T00:00:00Z", "invalid"),
      p("WeatherBridge AppStore", "ACTIVE", "IOS_APP_DEVELOPMENT", "2028-01-01T00:00:00Z", "dev"),
      p("WeatherBridge Widget AppStore", "ACTIVE", "IOS_APP_STORE", "2028-01-01T00:00:00Z", "w"),
    ],
  };
  assertEquals(pickProfile(body, "WeatherBridge AppStore")?.uuid, "new");
  assertEquals(pickProfile(body, "WeatherBridge Widget AppStore")?.uuid, "w");
  assertEquals(pickProfile(body, "Other"), null);
  assertEquals(pickProfile({}, "WeatherBridge AppStore"), null);
});
