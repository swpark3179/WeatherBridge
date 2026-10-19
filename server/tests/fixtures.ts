/** 테스트용 응답 생성기. 실제 API 응답 형식(data.go.kr JSON, Open-Meteo unixtime)을 따른다. */

/** KST 시각을 epoch 초로 */
export function kst(y: number, mo: number, d: number, h: number, mi = 0): number {
  return Date.UTC(y, mo - 1, d, h - 9, mi) / 1000;
}

function ymdhm(epochSec: number): { date: string; time: string } {
  const d = new Date((epochSec + 9 * 3600) * 1000);
  const p = (n: number) => String(n).padStart(2, "0");
  return {
    date: `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}`,
    time: `${p(d.getUTCHours())}${p(d.getUTCMinutes())}`,
  };
}

export interface KmaSlotSpec {
  t: number;
  pop: number;
  pcp?: string;
  tmp?: number;
}

/** getVilageFcst 응답 본문 */
export function kmaVilageBody(issuedAt: number, slots: KmaSlotSpec[]): string {
  const base = ymdhm(issuedAt);
  const item = (category: string, t: number, value: string) => {
    const f = ymdhm(t);
    return {
      baseDate: base.date,
      baseTime: base.time,
      category,
      fcstDate: f.date,
      fcstTime: f.time,
      fcstValue: value,
      nx: 60,
      ny: 127,
    };
  };
  const items = slots.flatMap((s) => [
    item("TMP", s.t, String(s.tmp ?? 15)),
    item("SKY", s.t, "1"),
    item("POP", s.t, String(s.pop)),
    item("PCP", s.t, s.pcp ?? "강수없음"),
  ]);
  return JSON.stringify({
    response: {
      header: { resultCode: "00", resultMsg: "NORMAL_SERVICE" },
      body: {
        dataType: "JSON",
        items: { item: items },
        pageNo: 1,
        numOfRows: 1000,
        totalCount: items.length,
      },
    },
  });
}

/** getUltraSrtNcst 응답 본문 */
export function kmaNcstBody(obsTime: number, values: Record<string, string>): string {
  const base = ymdhm(obsTime);
  const items = Object.entries(values).map(([category, obsrValue]) => ({
    baseDate: base.date,
    baseTime: base.time,
    category,
    nx: 60,
    ny: 127,
    obsrValue,
  }));
  return JSON.stringify({
    response: {
      header: { resultCode: "00", resultMsg: "NORMAL_SERVICE" },
      body: { items: { item: items }, totalCount: items.length },
    },
  });
}

/**
 * Open-Meteo 응답 본문. pops[model][i]는 시각 times[i]의 값(= 직전 1시간 확률).
 */
export function openMeteoBody(
  times: number[],
  pops: Record<string, Array<number | null>>,
  temps?: Record<string, Array<number | null>>,
): string {
  const hourly: Record<string, unknown> = { time: times };
  for (const [model, values] of Object.entries(pops)) {
    hourly[`precipitation_probability_${model}`] = values;
    hourly[`precipitation_${model}`] = values.map((v) => (v === null ? null : v >= 50 ? 1.2 : 0));
    hourly[`temperature_2m_${model}`] = temps?.[model] ?? values.map(() => 14);
  }
  return JSON.stringify({ latitude: 37.57, longitude: 126.98, utc_offset_seconds: 0, hourly });
}

/** URL 패턴별로 응답을 돌려주는 가짜 fetch. 호출 기록을 남긴다. */
export function routedFetch(routes: Array<[RegExp, () => string | Response]>) {
  const calls: string[] = [];
  const fn = (input: string) => {
    calls.push(input);
    const route = routes.find(([re]) => re.test(input));
    if (!route) return Promise.reject(new Error(`unexpected fetch ${input}`));
    const out = route[1]();
    return Promise.resolve(out instanceof Response ? out : new Response(out));
  };
  return { fn, calls };
}
