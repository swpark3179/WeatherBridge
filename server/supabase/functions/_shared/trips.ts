/**
 * 앱 "여행" 화면: 여행 기간의 날짜마다 목적지와 집의 하루 날씨, 그리고 집의 지난 기온.
 * 응답 형식은 ios/Packages/WeatherCore의 TripsResponse와 같고, 계약 샘플
 * ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/trips_response.json을 양쪽 테스트가 검증한다.
 *
 * 기온 비교("집 최근 3일보다 몇 도")는 앱(WeatherCore)이 한다. 서버는 원자료만 싣는다.
 * - 그 날 기온은 그 날 끝까지 닿는 Open-Meteo 모델들의 평균이고, 쓴 모델을 함께 싣는다.
 * - 집의 지난 기온은 모델별로 싣는다. 앱이 그 날과 같은 모델 묶음으로 기준을 만들어 모델 간 치우침을 뺀다.
 * 좌표는 싣지 않는다.
 */
import { aggregateDay } from "./aggregate.ts";
import type { Place, Trip } from "./db.ts";
import {
  type Deps,
  ensureForecasts,
  type EnsureResult,
  isTripWatched,
  openMeteoLocKey,
} from "./forecast_service.ts";
import type { ProviderForecast } from "./forecast_types.ts";
import {
  addDays,
  formatLocalDate,
  type LocalDate,
  localDateOf,
  parseLocalDate,
  zonedEpoch,
} from "./schedule.ts";
import {
  coveringDay,
  type ModelReach,
  OPEN_METEO_PROVIDERS,
  openMeteoReach,
  type TempHistory,
  tempHistory,
} from "./today.ts";

/** 하늘 상태에 쓰는 낮 시간 (현지 시, 끝 제외) */
export const DAYTIME_HOURS = { from: 8, to: 20 } as const;
/** 운량·적설은 그 시간의 이 비율 이상 값이 있을 때만 구한다 */
const MIN_COVERAGE = 0.75;

export interface TripRain {
  /** 계열마다 그 날 최고 강수확률의 가중 평균 (aggregateDay) */
  pop: number;
  agreeing: number;
  total: number;
  rainy: boolean;
}

/** 한 장소의 하루 날씨. 하루 경계는 그 장소의 시간대다. */
export interface TripDayWeather {
  /** 그 장소 현지 날짜의 0시 (epoch 초) */
  start: number;
  /** 남은 시간의 비 소식. 이미 지난 날이거나 예보가 닿지 않으면 null */
  rain: TripRain | null;
  /** 낮(DAYTIME_HOURS) 평균 운량(%) */
  cloud: number | null;
  /** 하루 적설(cm), 모델 평균 */
  snowCm: number | null;
  /** 0–24시 시간별 기온. 그 날 끝까지 닿는 Open-Meteo 모델의 평균 (providers에 쓴 모델) */
  temps: TempHistory | null;
}

export interface TripDay {
  /** 여행 날짜 "YYYY-MM-DD" (목적지 달력). 집도 같은 달력 날짜를 집 시간대로 본다. */
  date: string;
  /** 감시 밖(끝났거나 아직 먼 여행)이면 null */
  destination: TripDayWeather | null;
  home: TripDayWeather | null;
}

export interface TripSummary {
  id: string;
  name: string;
  /** 목적지 IANA 시간대 */
  tz: string;
  startDate: string;
  endDate: string;
  /** 예보를 받는 중인지 (끝나지 않았고 출발이 TRIP_LEAD_DAYS일 안) */
  watched: boolean;
  /** 아직 지나지 않은 여행 날짜. 집·목적지 모두에서 지난 날만 뺀다 */
  days: TripDay[];
}

export interface TripsResponse {
  generatedAt: number;
  threshold: number;
  /** 집. 등록하지 않았으면 null */
  home: {
    name: string;
    tz: string;
    /** 지난 7일~오늘 시간별 기온, Open-Meteo 모델마다 하나씩 (providers에 그 모델 하나) */
    recent: TempHistory[];
  } | null;
  /** 진행 중, 다가오는 여행(출발 순), 끝난 여행(최근 순) */
  trips: TripSummary[];
}

type Phase = "ongoing" | "upcoming" | "ended";

function phaseOf(trip: Trip, nowSec: number): Phase {
  const today = formatLocalDate(localDateOf(nowSec, trip.place.tz));
  if (trip.endDate < today) return "ended";
  return trip.startDate <= today ? "ongoing" : "upcoming";
}

const PHASE_ORDER: Record<Phase, number> = { ongoing: 0, upcoming: 1, ended: 2 };

/** 한 장소의 예보로 날짜별 하루 날씨를 만든다. 같은 날짜는 한 번만 계산한다. */
export class DayWeatherBuilder {
  private readonly models: ModelReach[];
  private readonly memo = new Map<string, TripDayWeather>();

  constructor(
    private readonly forecasts: ProviderForecast[],
    private readonly opts: { tz: string; nowSec: number; threshold: number },
  ) {
    this.models = openMeteoReach(forecasts);
  }

  day(date: string): TripDayWeather {
    let weather = this.memo.get(date);
    if (!weather) {
      weather = this.build(parseLocalDate(date));
      this.memo.set(date, weather);
    }
    return weather;
  }

  private build(date: LocalDate): TripDayWeather {
    const { tz, nowSec, threshold } = this.opts;
    const start = zonedEpoch(date, 0, 0, tz);
    const end = zonedEpoch(addDays(date, 1), 0, 0, tz);

    const from = Math.max(start, Math.floor(nowSec / 3600) * 3600);
    let rain: TripRain | null = null;
    if (from < end) {
      const agg = aggregateDay(this.forecasts, { from, to: end, threshold });
      if (agg.pop !== null) {
        rain = { pop: agg.pop, agreeing: agg.agreeing, total: agg.total, rainy: agg.rainy };
      }
    }

    // 그 날 마지막 정시까지 기온이 있는 모델만 (먼 날일수록 줄어든다)
    const { covering, temps } = coveringDay(this.models, { from: start, to: end });
    const hours: number[] = [];
    for (let t = Math.ceil(start / 3600) * 3600; t < end; t += 3600) hours.push(t);

    return {
      start,
      rain,
      cloud: daytimeCloud(covering, hours, start),
      snowCm: dailySnow(covering, hours),
      temps,
    };
  }
}

/** 낮 시간마다 모델 평균 운량을 구하고, 그 평균. 값이 있는 시간이 모자라면 null */
function daytimeCloud(models: ProviderForecast[], hours: number[], start: number): number | null {
  const daytime = hours.filter((t) => {
    const h = (t - start) / 3600;
    return h >= DAYTIME_HOURS.from && h < DAYTIME_HOURS.to;
  });
  const bySlot = models.map((f) => new Map(f.slots.map((s) => [s.t, s.cloud ?? null])));
  const means: number[] = [];
  for (const t of daytime) {
    const values = bySlot.map((m) => m.get(t)).filter((v): v is number => v != null);
    if (values.length > 0) means.push(values.reduce((a, b) => a + b, 0) / values.length);
  }
  if (means.length === 0 || means.length < daytime.length * MIN_COVERAGE) return null;
  return Math.round(means.reduce((a, b) => a + b, 0) / means.length);
}

/** 모델마다 하루 적설 합(값이 충분한 모델만)을 구해 평균 (cm, 소수 첫째 자리) */
function dailySnow(models: ProviderForecast[], hours: number[]): number | null {
  const wanted = new Set(hours);
  const sums: number[] = [];
  for (const f of models) {
    const values = f.slots.filter((s) => wanted.has(s.t) && s.snowCm != null).map((s) => s.snowCm!);
    if (values.length > 0 && values.length >= hours.length * MIN_COVERAGE) {
      sums.push(values.reduce((a, b) => a + b, 0));
    }
  }
  if (sums.length === 0) return null;
  return Math.round(sums.reduce((a, b) => a + b, 0) / sums.length * 10) / 10;
}

/** 여행 날짜 중 아직 지나지 않은 날. 집·목적지 중 날짜가 이른 쪽의 오늘부터 (예: 서울에서 본 호놀룰루 어제) */
function remainingDates(trip: Trip, home: Place | null, nowSec: number): string[] {
  const todays = [trip.place.tz, ...(home ? [home.tz] : [])]
    .map((tz) => formatLocalDate(localDateOf(nowSec, tz)));
  const earliest = todays.sort()[0];
  const dates: string[] = [];
  for (
    let d = parseLocalDate(trip.startDate);
    formatLocalDate(d) <= trip.endDate;
    d = addDays(d, 1)
  ) {
    const date = formatLocalDate(d);
    if (date >= earliest) dates.push(date);
  }
  return dates;
}

export interface LoadedTrips {
  home: Place | null;
  homeForecasts: ProviderForecast[];
  trips: Trip[];
  /** 감시 중인 여행 목적지의 예보 (trip id → 예보) */
  destinations: Map<string, ProviderForecast[]>;
}

/** 감시 중인 여행의 목적지와 집 예보를 캐시에서 꺼낸다(만료됐으면 새로 받음). 같은 위치는 한 번만. */
export async function loadTripForecasts(
  deps: Deps,
  home: Place | null,
  trips: Trip[],
): Promise<LoadedTrips> {
  const nowSec = Math.floor(deps.nowMs() / 1000);
  const byLoc = new Map<string, Promise<EnsureResult>>();
  const ensure = (place: Place) => {
    const key = openMeteoLocKey(place);
    let pending = byLoc.get(key);
    if (!pending) {
      pending = ensureForecasts(place, deps);
      byLoc.set(key, pending);
    }
    return pending;
  };
  const watched = trips.filter((t) => isTripWatched(t, nowSec));
  const [homeResult, ...results] = await Promise.all([
    home && watched.length > 0 ? ensure(home) : null,
    ...watched.map((t) => ensure(t.place)),
  ]);
  for (const r of [homeResult, ...results]) {
    if (r && r.errors.length > 0) console.error("trips: forecast errors", r.errors);
  }
  return {
    home,
    // 지난 기온(기준)은 감시 중인 여행이 없어도 실을 필요가 없다: 비교할 날씨가 없다.
    homeForecasts: homeResult?.forecasts ?? [],
    trips,
    destinations: new Map(watched.map((t, i) => [t.id, results[i].forecasts])),
  };
}

export function buildTrips(
  loaded: LoadedTrips,
  opts: { nowSec: number; threshold: number },
): TripsResponse {
  const { home, homeForecasts } = loaded;
  const homeDays = home ? new DayWeatherBuilder(homeForecasts, { ...opts, tz: home.tz }) : null;

  const trips = loaded.trips.map((trip) => {
    const forecasts = loaded.destinations.get(trip.id);
    const destination = forecasts
      ? new DayWeatherBuilder(forecasts, { ...opts, tz: trip.place.tz })
      : null;
    return {
      phase: phaseOf(trip, opts.nowSec),
      summary: {
        id: trip.id,
        name: trip.place.name,
        tz: trip.place.tz,
        startDate: trip.startDate,
        endDate: trip.endDate,
        watched: destination !== null,
        days: remainingDates(trip, home, opts.nowSec).map((date) => ({
          date,
          destination: destination?.day(date) ?? null,
          home: destination && homeDays ? homeDays.day(date) : null,
        })),
      },
    };
  });
  trips.sort((a, b) =>
    PHASE_ORDER[a.phase] - PHASE_ORDER[b.phase] ||
    (a.phase === "ended"
      ? b.summary.endDate.localeCompare(a.summary.endDate)
      : a.summary.startDate.localeCompare(b.summary.startDate))
  );

  return {
    generatedAt: opts.nowSec,
    threshold: opts.threshold,
    home: home
      ? {
        name: home.name,
        tz: home.tz,
        recent: homeForecasts.filter((f) => OPEN_METEO_PROVIDERS.has(f.provider))
          .map((f) => tempHistory([f], { nowSec: opts.nowSec, tz: home.tz }))
          .filter((h): h is TempHistory => h !== null),
      }
      : null,
    trips: trips.map((t) => t.summary),
  };
}
