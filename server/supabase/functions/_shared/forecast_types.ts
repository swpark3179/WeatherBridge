/** 상관된 예보끼리 묶는 계열. 같은 계열은 한 표로만 반영한다. */
export type Family = "kma" | "ecmwf" | "ncep" | "dwd";

export type ProviderId = "kma_short" | "om_ecmwf" | "om_gfs" | "om_icon";

export const PROVIDER_FAMILY: Record<ProviderId, Family> = {
  kma_short: "kma",
  om_ecmwf: "ecmwf",
  om_gfs: "ncep",
  om_icon: "dwd",
};

export interface HourSlot {
  /** 시작 시각 (epoch 초, UTC 정시) */
  t: number;
  /** 강수확률(%) */
  pop: number | null;
  /**
   * 확률이 가리키는 구간 길이(시간). 1이면 시간별 확률.
   * 3이면 t부터 3시간 구간 확률(기상청 연장구간)이라 시간별 종합에는 쓰지 않는다.
   */
  span: number;
  /** 구간 강수량(mm) */
  precipMm: number | null;
  /** 기온(°C, t 시각) */
  temp: number | null;
}

export interface ProviderForecast {
  provider: ProviderId;
  family: Family;
  /** 발표 시각(기상청) 또는 조회 기준 시각(Open-Meteo), epoch 초 */
  issuedAt: number;
  fetchedAt: number;
  slots: HourSlot[];
}

export interface Observation {
  locKey: string;
  /** 관측 시각 (epoch 초) */
  obsTime: number;
  /** 직전 1시간 강수량(mm) */
  rn1: number | null;
  /** 강수형태 코드 (0 없음, 1 비, 2 비/눈, 3 눈, 5 빗방울, 6 빗방울눈날림, 7 눈날림) */
  pty: number | null;
  t1h: number | null;
}

export type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export class ProviderError extends Error {
  constructor(readonly provider: string, message: string) {
    super(`${provider}: ${message}`);
  }
}
