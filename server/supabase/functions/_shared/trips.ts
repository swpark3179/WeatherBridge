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
import type { Place, Trip } from "./db.ts";
import {
  DayWeatherBuilder,
  OPEN_METEO_PROVIDERS,
  type TempHistory,
  type TripDayWeather,
} from "./day_weather.ts";
import {
  type Deps,
  ensureForecasts,
  type EnsureResult,
  isTripWatched,
  openMeteoLocKey,
} from "./forecast_service.ts";
import type { ProviderForecast } from "./forecast_types.ts";
import { addDays, formatLocalDate, localDateOf, parseLocalDate } from "./schedule.ts";
import { tempHistory } from "./today.ts";

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
