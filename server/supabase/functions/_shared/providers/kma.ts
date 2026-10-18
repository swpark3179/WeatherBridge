/**
 * 기상청 동네예보 조회서비스 (data.go.kr 15084084, VilageFcstInfoService_2.0)
 * - getVilageFcst: 단기예보 (시간별 POP 등)
 * - getUltraSrtNcst: 초단기실황 (관측, RN1 = 직전 1시간 강수량)
 */
import {
  type FetchFn,
  type HourSlot,
  type Observation,
  PROVIDER_FAMILY,
  ProviderError,
  type ProviderForecast,
} from "../forecast_types.ts";
import { type KmaGrid, kmaLocKey } from "../kma_grid.ts";
import { type KmaBase, kstToEpoch, latestUltraSrtNcstBase, latestVilageBase } from "../kma_time.ts";

const BASE_URL = "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0";
const PAGE_SIZE = 1000;
const MAX_PAGES = 4;

export function kmaUrl(
  operation: "getVilageFcst" | "getUltraSrtNcst",
  serviceKey: string,
  base: KmaBase,
  grid: KmaGrid,
  pageNo = 1,
): string {
  const params = new URLSearchParams({
    serviceKey, // data.go.kr '일반 인증키(Decoding)' 값 (여기서 인코딩됨)
    pageNo: String(pageNo),
    numOfRows: String(PAGE_SIZE),
    dataType: "JSON",
    base_date: base.baseDate,
    base_time: base.baseTime,
    nx: String(grid.nx),
    ny: String(grid.ny),
  });
  return `${BASE_URL}/${operation}?${params}`;
}

interface KmaFcstItem {
  baseDate: string;
  baseTime: string;
  category: string;
  fcstDate: string;
  fcstTime: string;
  fcstValue: string;
}

interface KmaNcstItem {
  baseDate: string;
  baseTime: string;
  category: string;
  obsrValue: string;
}

interface KmaPage<T> {
  items: T[];
  totalCount: number;
}

/** 응답 본문을 확인하고 항목을 꺼낸다. 인증 오류 등은 JSON 요청에도 XML로 오므로 함께 처리. */
export function parseKmaPage<T>(text: string): KmaPage<T> {
  let body: {
    response?: {
      header?: { resultCode?: string; resultMsg?: string };
      body?: { items?: { item?: T[] } | ""; totalCount?: number };
    };
  };
  try {
    body = JSON.parse(text);
  } catch {
    throw new ProviderError("kma", `JSON이 아닌 응답: ${text.slice(0, 200)}`);
  }
  const header = body.response?.header;
  if (header?.resultCode !== "00") {
    throw new ProviderError("kma", `resultCode ${header?.resultCode}: ${header?.resultMsg}`);
  }
  const items = body.response?.body?.items;
  return {
    items: (typeof items === "object" ? items.item : undefined) ?? [],
    totalCount: body.response?.body?.totalCount ?? 0,
  };
}

async function fetchAllPages<T>(
  url: (page: number) => string,
  fetchFn: FetchFn,
): Promise<T[]> {
  const all: T[] = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const res = await fetchFn(url(page), { signal: AbortSignal.timeout(8_000) });
    const { items, totalCount } = parseKmaPage<T>(await res.text());
    all.push(...items);
    if (all.length >= totalCount || items.length === 0) break;
  }
  return all;
}

/**
 * 단기예보 강수량(PCP) 문자열 → mm.
 * "강수없음" → 0, "1mm 미만" → 0.5, "30.0~50.0mm" → 40, "50.0mm 이상" → 50, "6.2mm" → 6.2.
 * 연장구간의 "약한 비" 같은 문구는 수치가 없어 null.
 */
export function parsePcp(value: string): number | null {
  const v = value.trim();
  if (v === "강수없음" || v === "0") return 0;
  if (v.includes("미만")) return 0.5;
  const range = v.match(/^([\d.]+)\s*~\s*([\d.]+)\s*mm$/);
  if (range) return (Number(range[1]) + Number(range[2])) / 2;
  const num = v.match(/^([\d.]+)\s*(mm)?(\s*이상)?$/);
  return num ? Number(num[1]) : null;
}

/**
 * 단기예보 항목들 → 시간별 슬롯. 앞 슬롯과 3시간 간격인 값(연장구간)은 span=3으로 표시해
 * 시간별 종합에서 빼고, 1시간 간격 구간의 마지막 값은 시간별 값으로 남긴다.
 */
export function parseVilageItems(items: KmaFcstItem[], fetchedAt: number): ProviderForecast {
  if (items.length === 0) throw new ProviderError("kma", "예보 항목이 없습니다");
  const byTime = new Map<number, { pop: number | null; pcp: number | null; tmp: number | null }>();
  for (const item of items) {
    const t = kstToEpoch(item.fcstDate, item.fcstTime);
    const slot = byTime.get(t) ?? { pop: null, pcp: null, tmp: null };
    if (item.category === "POP") slot.pop = Number(item.fcstValue);
    else if (item.category === "PCP") slot.pcp = parsePcp(item.fcstValue);
    else if (item.category === "TMP") slot.tmp = Number(item.fcstValue);
    byTime.set(t, slot);
  }
  const times = [...byTime.keys()].filter((t) => byTime.get(t)!.pop !== null).sort((a, b) => a - b);
  const slots: HourSlot[] = times.map((t, i) => {
    const gap = i > 0 ? (t - times[i - 1]) / 3600 : times.length > 1 ? (times[1] - t) / 3600 : 1;
    const v = byTime.get(t)!;
    return { t, pop: v.pop, span: Math.min(Math.max(gap, 1), 3), precipMm: v.pcp, temp: v.tmp };
  });
  return {
    provider: "kma_short",
    family: PROVIDER_FAMILY.kma_short,
    issuedAt: kstToEpoch(items[0].baseDate, items[0].baseTime),
    fetchedAt,
    slots,
  };
}

export async function fetchKmaShort(opts: {
  serviceKey: string;
  grid: KmaGrid;
  nowMs: number;
  fetchFn?: FetchFn;
}): Promise<ProviderForecast> {
  const base = latestVilageBase(opts.nowMs);
  const items = await fetchAllPages<KmaFcstItem>(
    (page) => kmaUrl("getVilageFcst", opts.serviceKey, base, opts.grid, page),
    opts.fetchFn ?? fetch,
  );
  return parseVilageItems(items, Math.floor(opts.nowMs / 1000));
}

export function parseNcstItems(items: KmaNcstItem[], grid: KmaGrid): Observation {
  if (items.length === 0) throw new ProviderError("kma", "실황 항목이 없습니다");
  const value = (category: string) => {
    const raw = items.find((i) => i.category === category)?.obsrValue;
    if (raw === undefined) return null;
    const n = Number(raw);
    // 결측값은 -998.9 등 큰 음수로 온다
    return Number.isFinite(n) && n > -900 ? n : null;
  };
  return {
    locKey: kmaLocKey(grid),
    obsTime: kstToEpoch(items[0].baseDate, items[0].baseTime),
    rn1: value("RN1"),
    pty: value("PTY"),
    t1h: value("T1H"),
  };
}

export async function fetchKmaObservation(opts: {
  serviceKey: string;
  grid: KmaGrid;
  nowMs: number;
  fetchFn?: FetchFn;
}): Promise<Observation> {
  const base = latestUltraSrtNcstBase(opts.nowMs);
  const items = await fetchAllPages<KmaNcstItem>(
    (page) => kmaUrl("getUltraSrtNcst", opts.serviceKey, base, opts.grid, page),
    opts.fetchFn ?? fetch,
  );
  return parseNcstItems(items, opts.grid);
}
