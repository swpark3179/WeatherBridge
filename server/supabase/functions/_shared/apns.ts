/**
 * APNs 토큰 인증(.p8) 발송 모듈.
 * - 기기 발송: POST /3/device/<token> (알림, Live Activity push-to-start/업데이트)
 * - 브로드캐스트(iOS 18+): 채널 생성 POST /1/apps/<bundle>/channels, 발송 POST /4/broadcasts/apps/<bundle>
 * Live Activity 페이로드 키는 ios/Packages/WeatherCore의 CommuteActivityAttributes / CommuteState와 같다.
 */
import { signEs256Jwt } from "./es256.ts";

export type ApnsEnv = "sandbox" | "production";

export const APNS_HOSTS: Record<ApnsEnv, { device: string; broadcast: string; manage: string }> = {
  sandbox: {
    device: "https://api.sandbox.push.apple.com",
    broadcast: "https://api-broadcast.sandbox.push.apple.com",
    manage: "https://api-manage-broadcast.sandbox.push.apple.com:2195",
  },
  production: {
    device: "https://api.push.apple.com",
    broadcast: "https://api-broadcast.push.apple.com",
    manage: "https://api-manage-broadcast.push.apple.com:2196",
  },
};

export const ATTRIBUTES_TYPE = "CommuteActivityAttributes";

// ---------- 데이터 계약 (WeatherCore와 동일) ----------

export interface CommuteAttributes {
  windowEnd: number; // 출근 시각 T, epoch 초
  firstHour: number; // pops[0]의 현지 시각
}

export interface PlaceBrief {
  name: string;
  temp: number | null;
  pops: number[];
  maxPop: number;
  rainWindow: string | null;
}

export interface CommuteState {
  headline: string;
  highlight: boolean;
  places: PlaceBrief[];
  updatedAt: number; // epoch 초
}

// ---------- 페이로드 빌더 ----------

export function buildLiveActivityStart(opts: {
  now: number;
  attributes: CommuteAttributes;
  state: CommuteState;
  alert: { title: string; body: string };
  channelId?: string;
}) {
  return {
    aps: {
      timestamp: opts.now,
      event: "start",
      "content-state": opts.state,
      "attributes-type": ATTRIBUTES_TYPE,
      attributes: opts.attributes,
      alert: opts.alert,
      // 종료 푸시가 유실돼도 T 이후엔 '지난 정보'로 표시되게 한다.
      "stale-date": opts.attributes.windowEnd,
      ...(opts.channelId ? { "input-push-channel": opts.channelId } : {}),
    },
  };
}

export function buildLiveActivityUpdate(
  opts: { now: number; state: CommuteState; staleDate: number },
) {
  return {
    aps: {
      timestamp: opts.now,
      event: "update",
      "content-state": opts.state,
      "stale-date": opts.staleDate,
    },
  };
}

export function buildLiveActivityEnd(
  opts: { now: number; state: CommuteState; dismissalDate: number },
) {
  return {
    aps: {
      timestamp: opts.now,
      event: "end",
      "content-state": opts.state,
      "dismissal-date": opts.dismissalDate,
    },
  };
}

export function liveActivityTopic(bundleId: string): string {
  return `${bundleId}.push-type.liveactivity`;
}

// ---------- 공급자 토큰 (ES256 JWT) ----------

export interface ApnsKey {
  teamId: string;
  keyId: string;
  /** .p8 파일 내용 (PEM, PKCS#8) */
  privateKeyPem: string;
}

export function createProviderToken(key: ApnsKey, nowSec: number): Promise<string> {
  return signEs256Jwt(
    { alg: "ES256", kid: key.keyId },
    { iss: key.teamId, iat: nowSec },
    key.privateKeyPem,
  );
}

/**
 * APNs는 토큰을 20분보다 자주 갱신하면 거부하고, 60분이 지나면 만료시킨다 → 50분간 재사용.
 * (Phase 1 이후에는 콜드 스타트 대비 DB에 저장)
 */
export class ProviderTokenCache {
  #token: string | null = null;
  #issuedAt = 0;

  constructor(private readonly key: ApnsKey, private readonly maxAgeSec = 50 * 60) {}

  async get(nowSec: number): Promise<string> {
    if (!this.#token || nowSec - this.#issuedAt >= this.maxAgeSec) {
      this.#token = await createProviderToken(this.key, nowSec);
      this.#issuedAt = nowSec;
    }
    return this.#token;
  }
}

// ---------- 요청 ----------

export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;

export interface ApnsResult {
  status: number;
  apnsId: string | null;
  channelId: string | null;
  body: unknown;
}

export function sendToDevice(opts: {
  env: ApnsEnv;
  providerToken: string;
  deviceToken: string;
  topic: string;
  pushType: "alert" | "liveactivity" | "background";
  priority: 5 | 10;
  payload: unknown;
  expiration?: number;
}, fetchFn: FetchFn = fetch): Promise<ApnsResult> {
  const headers: Record<string, string> = {
    authorization: `bearer ${opts.providerToken}`,
    "apns-topic": opts.topic,
    "apns-push-type": opts.pushType,
    "apns-priority": String(opts.priority),
  };
  if (opts.expiration !== undefined) headers["apns-expiration"] = String(opts.expiration);
  return request(
    fetchFn,
    `${APNS_HOSTS[opts.env].device}/3/device/${opts.deviceToken}`,
    headers,
    opts.payload,
  );
}

export function createChannel(opts: {
  env: ApnsEnv;
  providerToken: string;
  bundleId: string;
  /** 0 = 저장 안 함, 1 = 최근 1건 저장(오프라인 기기에 최신 상태 전달) */
  storagePolicy: 0 | 1;
}, fetchFn: FetchFn = fetch): Promise<ApnsResult> {
  return request(
    fetchFn,
    `${APNS_HOSTS[opts.env].manage}/1/apps/${opts.bundleId}/channels`,
    { authorization: `bearer ${opts.providerToken}` },
    { "message-storage-policy": opts.storagePolicy, "push-type": "LiveActivity" },
  );
}

export function broadcast(opts: {
  env: ApnsEnv;
  providerToken: string;
  bundleId: string;
  channelId: string;
  priority: 1 | 5 | 10;
  /** 0이면 저장하지 않고 한 번만 시도 */
  expiration: number;
  payload: unknown;
}, fetchFn: FetchFn = fetch): Promise<ApnsResult> {
  return request(
    fetchFn,
    `${APNS_HOSTS[opts.env].broadcast}/4/broadcasts/apps/${opts.bundleId}`,
    {
      authorization: `bearer ${opts.providerToken}`,
      "apns-channel-id": opts.channelId,
      "apns-push-type": "liveactivity",
      "apns-priority": String(opts.priority),
      "apns-expiration": String(opts.expiration),
    },
    opts.payload,
  );
}

async function request(
  fetchFn: FetchFn,
  url: string,
  headers: Record<string, string>,
  payload: unknown,
): Promise<ApnsResult> {
  const res = await fetchFn(url, {
    method: "POST",
    headers: { ...headers, "content-type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10_000),
  });
  const text = await res.text();
  let body: unknown = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }
  }
  return {
    status: res.status,
    apnsId: res.headers.get("apns-id") ?? res.headers.get("apns-request-id"),
    channelId: res.headers.get("apns-channel-id"),
    body,
  };
}
