// App Store Connect API로 App Store 프로비저닝 프로파일을 이름으로 찾아 이 Mac에 설치한다.
// ios-testflight 워크플로가 수동 서명 전에 실행한다. 프로파일 내용은 출력하지 않는다.
//
//   ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8="$(cat AuthKey.p8)" \
//     deno run --allow-env --allow-net=api.appstoreconnect.apple.com --allow-write \
//     scripts/asc_profiles.ts "WeatherBridge AppStore" "WeatherBridge Widget AppStore"
import { signEs256Jwt } from "../supabase/functions/_shared/es256.ts";

const API = "https://api.appstoreconnect.apple.com";

export interface AscKey {
  keyId: string;
  issuerId: string;
  privateKeyPem: string;
}

export interface Profile {
  name: string;
  uuid: string;
  profileType: string;
  expirationDate: string;
  profileContent: string;
}

/** ASC API 토큰. 유효 시간은 최대 20분이다. */
export function ascToken(key: AscKey, nowSec: number): Promise<string> {
  return signEs256Jwt(
    { alg: "ES256", kid: key.keyId, typ: "JWT" },
    { iss: key.issuerId, iat: nowSec, exp: nowSec + 10 * 60, aud: "appstoreconnect-v1" },
    key.privateKeyPem,
  );
}

export function profilesUrl(name: string): string {
  const q = new URLSearchParams({
    "filter[name]": name,
    "fields[profiles]": "name,profileType,profileState,profileContent,uuid,expirationDate",
    limit: "20",
  });
  return `${API}/v1/profiles?${q}`;
}

/** 이름이 정확히 같고 유효한 App Store 프로파일 중 만료가 가장 늦은 것 */
export function pickProfile(body: unknown, name: string): Profile | null {
  const data = (body as { data?: Array<{ attributes?: Record<string, string> }> }).data ?? [];
  const candidates = data
    .map((d) => d.attributes ?? {})
    .filter((a) =>
      a.name === name && a.profileState === "ACTIVE" && a.profileType === "IOS_APP_STORE" &&
      a.profileContent
    )
    .sort((a, b) => (b.expirationDate ?? "").localeCompare(a.expirationDate ?? ""));
  const a = candidates[0];
  return a
    ? {
      name: a.name,
      uuid: a.uuid,
      profileType: a.profileType,
      expirationDate: a.expirationDate,
      profileContent: a.profileContent,
    }
    : null;
}

function decodeBase64(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

async function main(names: string[]) {
  const env = (k: string) => {
    const v = Deno.env.get(k)?.trim();
    if (!v) throw new Error(`${k} 환경 변수가 없습니다`);
    return v;
  };
  const key = {
    keyId: env("ASC_KEY_ID"),
    issuerId: env("ASC_ISSUER_ID"),
    privateKeyPem: env("ASC_KEY_P8"),
  };
  const token = await ascToken(key, Math.floor(Date.now() / 1000));
  // Xcode 16부터는 UserData 폴더를 읽고, 이전 버전은 MobileDevice 폴더를 읽는다.
  const home = env("HOME");
  const dirs = [
    `${home}/Library/Developer/Xcode/UserData/Provisioning Profiles`,
    `${home}/Library/MobileDevice/Provisioning Profiles`,
  ];
  let missing = 0;
  for (const name of names) {
    const res = await fetch(profilesUrl(name), {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(20_000),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      const errors =
        (body as { errors?: Array<{ status?: string; title?: string; detail?: string }> })
          .errors ?? [];
      console.error(`::error::ASC API ${res.status} (${name}): ${JSON.stringify(errors)}`);
      missing++;
      continue;
    }
    const profile = pickProfile(body, name);
    if (!profile) {
      console.error(
        `::error::"${name}" 이름의 유효한 App Store 프로파일이 없습니다 (docs/setup.md "App Store 프로파일")`,
      );
      missing++;
      continue;
    }
    const bytes = decodeBase64(profile.profileContent);
    for (const dir of dirs) {
      await Deno.mkdir(dir, { recursive: true });
      await Deno.writeFile(`${dir}/${profile.uuid}.mobileprovision`, bytes);
    }
    console.log(`설치: ${profile.name} (${profile.uuid}, 만료 ${profile.expirationDate})`);
  }
  if (missing) Deno.exit(1);
}

if (import.meta.main) {
  await main(Deno.args);
}
