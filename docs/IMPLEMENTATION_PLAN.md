# WeatherBridge — 단계적 구현 계획

## Context
- 빈 저장소(README만 존재)에서 시작하는 신규 모바일 앱.
- 목표: **내 지역(집·회사) 특화 날씨**, 특히 **시간대별 강수확률**을 여러 무료 날씨 소스로 비교·종합.
- 핵심 기능
  1. 출근시간 T 기준 **T-60분 ~ T 동안 잠금화면 브리핑**. 오늘 집·회사 중 비 올 가능성이 있는 시간대가 있으면 강조.
  2. 지정 시각에 **집·회사 오늘 날씨 요약 알림**.
  3. **여행 모드**: 기간·지역(국내/해외)을 등록하면 출발 전까지 예보 변화를 계속 추적. 출발일에는 집 날씨도 함께.
  4. **다중 무료 날씨 소스 비교·종합**(시간대별 강수확률 중심).
- 사용자 결정: Android + iOS 동시 / 온디바이스 + 경량 서버 / 여행지 국내+해외 / 개인·지인용 배포(스토어 공개 X).

---

## 1. 기술 선택

### 앱: Kotlin Multiplatform + Compose Multiplatform
- 선택 이유
  - 이 앱의 핵심(잠금화면 브리핑, 정시 알림)은 **앱 화면이 아니라 백그라운드·시스템 영역**에서 동작하고, 이 부분은 어떤 프레임워크든 네이티브(Kotlin/Swift) 코드가 필수.
  - KMP는 Android 쪽이 100% 네이티브 Kotlin이라 알람·워커·Live Update 알림이 **앱 UI와 같은 모델·API 클라이언트·설정 저장소를 그대로 공유**(브리지·중복 DTO 없음). 백그라운드에서 별도 엔진(Dart/JS)을 띄우지 않아 삼성 백그라운드 제약에 강함.
  - 주 사용 기기(갤럭시)의 최신 API(Android 16 Live Update, One UI Now Bar)를 즉시 사용 가능.
  - Compose Multiplatform iOS는 1.8(2025-05)부터 stable → iOS 앱 화면도 공유.
  - 언어 수: Kotlin + Swift(소량) + TypeScript(서버). (Flutter안은 Dart가 추가돼 4개 언어)
- 주요 라이브러리: Ktor Client, kotlinx.serialization, **kotlinx-datetime**(타임존), Koin, Navigation Compose, supabase-kt, DataStore(KMP), Firebase Messaging(Android 전용), 차트는 Compose Canvas 직접 구현(시간별 막대가 단순).
- Swift로 직접 작성할 부분(iOS): Widget Extension(SwiftUI: Live Activity + 잠금화면 위젯), ActivityKit 브리지(push-to-start 토큰 관찰 → Kotlin 인터페이스로 전달), APNs 등록.

### 서버: Supabase (무료 티어, 서울 리전)
- Postgres + Edge Functions(Deno/TypeScript) + `pg_cron`/`pg_net` + 익명 인증 + RLS.
- 역할
  - **모든 날씨 API 키 보관**(Edge secret; 앱에 포함 X)
  - **예보 수집·정규화·종합의 유일한 구현** + 캐시 → 앱 화면·Android 워커·iOS 푸시가 같은 결과 사용
  - **iOS 푸시**(요약 알림, Live Activity 시작/갱신/종료) — iOS는 백그라운드 실행이 보장되지 않아 서버 푸시가 사실상 필수. iOS는 **APNs 직접 발송**(Firebase 미사용).
  - **여행지 예보 추적**(양 플랫폼 공통), Android에는 FCM으로 알림.
- **Android는 기기에서 스케줄·알림**(정확 알람). 데이터는 서버 `briefing` 호출, 실패 시 "마지막 캐시 + Open-Meteo 직접 조회(저하 모드 표시)".

### 날씨 소스 (2026-10 무료 조건 확인)
| 소스 | 강수확률 필드 | 무료 범위 | 해상도 | 용도 |
|---|---|---|---|---|
| 기상청 단기예보 `getVilageFcst` | `POP` % | ~3~4일 | 1시간(연장구간 3시간 가능) | 국내 기준(가중치↑) |
| 기상청 중기예보 `getMidLandFcst` | `rnSt` | 4~10일 | 오전/오후·일 | 국내 여행 |
| Open-Meteo (키 없음, 비상업 1만/일) | 모델별 `precipitation_probability` | 16일 | 1시간 | ECMWF·GFS·ICON 3개 계열 비교, 해외, 폴백 |
| Apple WeatherKit REST | `precipitationChance` | ~10일 | 1시간 | 독자 블렌드(애플 개발자 멤버십 — iOS용으로 어차피 필요) |
| Tomorrow.io (500/일) | `precipitationProbability` | ~5일 | 1시간 | 비교 |
| WeatherAPI.com | `chance_of_rain` | 3일 | 1시간 | 비교 |
| OpenWeatherMap 5day/3h | `pop`(0~1) | 5일 | 3시간 블록 | 비교(구간 단위) |
| Visual Crossing (1000건/일) | `precipprob` | 15일 | 1시간 | 여행(원거리) |
| Pirate Weather (1만/월) | `precipProbability` | 7일 | 1시간 | 해외(북미) |
- 제외: Google Weather(한국 예보 미지원), AccuWeather(무료 종료), MET Norway(한국 강수확률 없음), Open-Meteo의 KMA 모델(2026-03 이후 갱신 중단·POP 없음).
- 해외 지점은 기상청 소스 자동 제외. data.go.kr 장애(2025-09~10 전례) 대비 KMA API Hub를 보조 엔드포인트로 검토.

---

## 2. 전체 구조

```
WeatherBridge/
├─ app/
│  ├─ composeApp/src/
│  │  ├─ commonMain/   domain(Place, Schedule, Trip, HourSlot, RainLevel, Briefing)
│  │  │                data(Ktor API, supabase-kt, DataStore 설정, 캐시, repositories)
│  │  │                ui(onboarding, dashboard, compare, trips, settings — Compose)
│  │  ├─ androidMain/  MainActivity, location, FCM 서비스,
│  │  │                briefing/ CommuteScheduler.kt(정확 알람·재등록), AlarmReceiver.kt,
│  │  │                BootReceiver.kt, BriefingWorker.kt(expedited), CommuteNotification.kt
│  │  │                (ongoing/Live Update), SummaryNotification.kt
│  │  └─ iosMain/      MainViewController, 플랫폼 브리지 인터페이스 구현 연결
│  └─ iosApp/          Xcode 프로젝트: AppDelegate(APNs), LiveActivityBridge.swift,
│                      CommuteWidget/ (CommuteLiveActivity.swift, LockScreenWidget.swift)
├─ server/supabase/
│  ├─ migrations/      스키마, RLS, pg_cron 잡, Vault 시크릿 참조
│  └─ functions/
│     ├─ _shared/providers/ kma_short.ts, kma_mid.ts, open_meteo.ts, weatherkit.ts,
│     │                     tomorrow.ts, weatherapi.ts, owm.ts, visual_crossing.ts, pirate.ts
│     ├─ _shared/ kma_grid.ts, normalize.ts, aggregate.ts, briefing.ts, schedule.ts,
│     │           cache.ts, quota.ts, clock.ts(테스트용 주입 시계), push/apns.ts, push/fcm.ts
│     ├─ refresh/     (cron: 등록 위치별 예보 수집 → forecast_cache, 예보·관측 로그 적재)
│     ├─ forecast/    (장소별 종합 예보 — 캐시만 읽음)
│     ├─ briefing/    (요약/출근 카드 가공)
│     ├─ dispatch/    (cron 5분: iOS 요약·Live Activity 수명주기, Android 백업 트리거)
│     └─ trip-watch/  (여행 스냅샷·변화 감지·알림)
├─ docs/  (API 키 발급, 배포·설치 가이드, 갤럭시/아이폰 설정 가이드)
└─ .github/workflows/ (Android 빌드·테스트, deno lint/test, macOS iOS 빌드, keep-alive)
```

### 주요 테이블
- `places`: kind(home/office/trip), lat/lon(약 1km로 스냅해 저장), IANA tz, kma_nx/ny, kma_mid_region
- `schedules`: 출근시간(현지시각)+tz, 요일별 on/off, 요약 시각, 공휴일 건너뛰기, "오늘 건너뛰기/휴가" 기간
- `trips`: place, 시작/종료일(목적지 기준), 출발 시각
- `devices`: platform, fcm_token, apns_token, **apns_env**(sandbox/production), LA 채널 ID, device_key 해시, last_armed/last_fetch
- `forecast_cache`, `forecast_log`(소스별 예보 기록), `obs_log`(기상청 실황 RN1/PTY), `trip_snapshots`, `dispatch_log`(unique: user, kind, local_date), `quota_ledger`

### 서버 운영 원칙
- **수집과 발송 분리**: `refresh`가 캐시를 채우고(기상청은 발표시각+15분, 그 외 1시간), `briefing`/`dispatch`는 캐시만 읽음 → Edge Function CPU 2초/150초 제한 회피. 각 소스는 개별 타임아웃 + `Promise.allSettled`.
- pg_cron → Edge 호출: Vault의 비밀값을 커스텀 헤더로 전달, 함수는 `--no-verify-jwt` 배포, 즉시 202 반환 후 `EdgeRuntime.waitUntil`로 처리.
- **APNs**: 토큰 인증(.p8) JWT를 DB에 저장해 재사용(20~60분 주기 갱신 규칙 준수).
- **무료 한도 장부**(`quota.ts`): Tomorrow 500/일, Visual Crossing 1000/일, Pirate 1만/월 초과 방지.
- **일시정지 방지**: GitHub Actions 일일 keep-alive 호출 + `dispatch` 마지막 실행 시각을 앱이 확인해 이상 시 경고 배너.
- 시간: 예보 시각은 UTC 저장·지점 tz로 표시, 기상청 base_time은 고정 +09:00로 계산하고 미발표 시 직전 발표 사용, 일정은 현지시각+IANA tz(DST 23/25시간 날 처리).

### 강수확률 종합 알고리즘 (`aggregate.ts`)
1. **정규화**: % 단위, UTC 정시 시작 슬롯. Open-Meteo "직전 1시간" 라벨 보정(관측값으로 검증 후 확정).
2. **구간 확률 분리**: OWM 3시간·기상청 연장 3시간·중기 오전/오후 값은 "구간 확률"이라 시간별 값에 복사하지 않음 → 시간별 종합에는 1시간 해상도 소스만, 구간 소스는 "비 구간/반나절" 단위 종합에만 사용.
3. **계열 묶기**(상관 소스 중복 방지): KMA / ECMWF계(Open-Meteo IFS, Pirate) / NCEP계(GFS) / DWD계(ICON) / 독자 블렌드(WeatherKit, Tomorrow, WeatherAPI, VC). 계열 내 평균 → 계열 간 가중 평균(국내 KMA 1.5, 기타 1.0).
4. **예보 범위별 고정 소스 세트**: 범위 경계에서 참여 소스가 바뀌어 그래프가 튀는 것을 방지(구간 경계 표시).
5. 시간별 출력: 종합 확률, 최소~최대, 합의도("6개 계열 중 4개 ≥ 임계값"), 참여 소스 수.
6. **등급**: 없음 <20 / 낮음 20–39 / 보통 40–59 / 높음 ≥60. 편차 ≥40%p면 "소스 간 의견 갈림".
7. **강조 규칙**: 오늘 남은 시간 중 집 또는 회사에서 `종합 ≥ 임계값(기본 30%, 설정 가능)` 또는 `기상청 ≥ 60%` 또는 `2개 이상 계열 ≥ 60%` → 강조. 연속 시간을 묶어 "☔ 회사 15–18시 최대 70% (5개 계열 중 4개)"로 문장화.

---

## 3. 단계별 구현 계획

### Phase 0 — 준비 + 기술 검증(스파이크)
1. 계정·키 (docs/setup.md에 절차 정리)
   - data.go.kr: 기상청 단기예보(15084084)·중기예보·특일정보 활용신청
   - Apple Developer Program(유료, 연 $99): 푸시·Live Activity·WeatherKit·배포에 필수
   - Firebase(Android FCM 전용), Supabase(서울 리전), Tomorrow.io·WeatherAPI·OpenWeatherMap·Visual Crossing·Pirate Weather 키
2. 저장소 골격: KMP 템플릿(`composeApp` + `iosApp`), `server/supabase` 초기화, CI(Android 빌드·단위 테스트, deno lint/test, macOS 러너 iOS 빌드 + fastlane match 서명).
3. **스파이크(본 개발 전 실기기 확인)**
   - iOS: push-to-start + `input-push-channel`(브로드캐스트 채널) → 채널로 업데이트 → `end` + `stale-date`로 T에 확실히 사라지는지 (Apple Push Notifications Console 사용)
   - Android 16/One UI 8: Live Update 승격·Now Bar 노출, 일반 ongoing 알림의 잠금화면 표시, `ProgressStyle` 세그먼트로 시간별 강수 막대 표현 가능 여부
   - Supabase Edge → APNs HTTP/2 발송, Edge → `apis.data.go.kr` 접근
4. 결정 확정: iOS 최소 버전 **18**(브로드캐스트 채널), 배포 방식
   - iOS: TestFlight 외부 테스트(공개 링크, 최초 1회 베타 심사, 90일 만료) — 개발 중엔 Ad Hoc
   - Android: Firebase App Distribution(APK). 사이드로드라 `USE_EXACT_ALARM` 선언 가능(설치 시 자동 허용) — 스토어 공개로 바뀌면 `SCHEDULE_EXACT_ALARM`으로 전환.

### Phase 1 — 서버 예보 엔진 (기상청 + Open-Meteo)
1. `kma_grid.ts`(위경도→nx/ny Lambert 변환), base_time 계산(KST, 미발표 시 직전).
2. 어댑터: **기상청 단기 + Open-Meteo(ECMWF/GFS/ICON 모델별)** → 첫날부터 4개 독립 계열 비교 가능. 어댑터는 `HourSlot[]` + 메타(발표시각, 범위, 해상도) 반환.
3. `refresh` cron + `forecast_cache`, `forecast`/`briefing` 함수, `aggregate.ts`.
4. **예보·관측 로그 적재 시작**(`forecast_log`, 기상청 초단기실황 RN1/PTY → `obs_log`) — Phase 6 정확도 가중치에 수개월 데이터 필요.
5. 테스트: 그리드 변환 기준값(서울시청 → 60,127), 어댑터 픽스처 정규화, 종합(계열 묶기·누락 소스·구간 확률), 주입 시계로 base_time·DST 경계.

### Phase 2 — 앱 MVP + 지정 시각 요약 알림
1. 익명 로그인 + 기기 등록(재설치 대비 복구 코드), 온보딩: 집·회사 위치(현재 위치 / Open-Meteo Geocoding `language=ko` 검색).
2. **오늘 화면**: 집·회사 카드 — 시간대별 강수확률 막대(등급 색), 비 구간 강조 배너, 기온·하늘 보조, 갱신 시각, 저하 모드 표시.
3. **비교 화면(기본)**: 소스×시간 히트맵, 종합·편차·합의도.
4. 설정: 출근시간·요일, 요약 시각, 강수 임계값, 데이터 출처 표기(Open-Meteo CC BY, WeatherKit 로고·법적 링크 등).
5. **요약 알림**
   - Android: 요약 시각 정확 알람 → `BriefingWorker`가 `briefing` 조회(디바이스 키 인증) → BigText 알림. 재부팅·앱 업데이트·시간/시간대 변경·권한 변경 시 재등록 + 일일 WorkManager 자가 점검.
   - iOS: `dispatch`가 요약 시각에 APNs 알림(서버 생성 문구) 발송, `dispatch_log`로 중복 방지.
6. 온보딩 가이드: 알림 권한, 삼성 배터리 "절전 예외 앱", One UI 잠금화면 알림 "카드" 표시, Auto Blocker/Play Protect 안내(사이드로드).

### Phase 3 — 출근 시간 잠금화면 브리핑
1. 공통: 공휴일(특일정보 월 1회 갱신 + 내장 폴백 목록), 요일별 on/off, "오늘 건너뛰기/휴가" 토글 → 요약·출근 브리핑 모두 적용.
2. Android
   - T-75 미리 조회 → T-60 캐시로 즉시 ongoing·`VISIBILITY_PUBLIC` 알림 게시, `setWhen(T)` 카운트다운, `timeoutAfter`로 T에 제거 + T 알람에서 확실히 취소.
   - 15분 간격 갱신(그보다 짧게 하지 않음 — Doze 제한).
   - Android 16+에서 가능하면 Live Update 승격(`setRequestPromotedOngoing`, `setShortCriticalText("☔70%")`). 색상 사용 불가 → 강조는 텍스트로("☔ 회사 15시 70%"). 불가 시 일반 ongoing.
   - 강조 시 소리 1회 채널 / 평상시 무음 채널.
   - **서버 백업**: 기기가 "T 예약됨"을 서버에 보고, T-55까지 조회 기록이 없으면 `dispatch`가 FCM 알림 메시지 발송.
3. iOS
   - Widget Extension(SwiftUI): 잠금화면(집/회사 한 줄씩 + 오늘 시간대별 강수 미니 막대, 강조 시 색/아이콘), Dynamic Island(☔최대확률), 카운트다운은 `Text(timerInterval:)`.
   - `dispatch`: T-60 push-to-start(알림 포함, `input-push-channel` 지정, `stale-date`=T) → 내용이 바뀔 때만 채널로 업데이트(priority 5) → T에 `end`(priority 10). 페이로드 4KB 이내(시간별 확률은 정수 배열).
   - 앱 실행 시 T가 지난 활동은 즉시 종료.
   - **폴백**: 잠금화면 위젯(WidgetKit 시간대별 타임라인 엔트리로 T-60~T에만 상세 표시) + time-sensitive 알림.
4. 강조 판단은 서버 `aggregate.ts` 결과 그대로 사용(양 플랫폼 동일).

### Phase 4 — 나머지 소스 + 비교 화면 완성
1. WeatherKit(서버 JWT 서명), Tomorrow.io, WeatherAPI, OpenWeatherMap(구간 확률) 어댑터 + `quota_ledger`.
2. 비교 화면: 소스·계열별 on/off, 구간 소스 별도 표시, 범위 경계 표시, 소스 간 의견 갈림 하이라이트.
3. 야간 실 API 스모크 테스트(소스별 응답 형식 변경 감지).

### Phase 5 — 여행 모드 (국내 → 해외)
1. 여행 등록: 목적지 검색, 기간(목적지 tz 기준), 출발 시각. 출발일 판단은 집 tz 기준.
2. `trip-watch` 재조회 주기
   - D-16~D-11: 1일 1회(Open-Meteo·Visual Crossing·WeatherKit 범위)
   - D-10~D-4: 1일 2회(국내는 기상청 중기 06/18시 발표 후)
   - D-3~당일: 3시간마다(기상청 단기 발표 직후)
3. `trip_snapshots`에 날짜·오전/오후별 종합 저장 → 상세 화면 **예보 변화 추이 그래프**("10/25 오후 30%→50%→70%").
4. 변화 알림: 계열별로 감지, **등급이 바뀌고 ±20%p 이상 변화가 2회 연속**일 때만 발송(소스 범위 진입에 의한 가짜 변화 방지), 여행당 하루 1회(D-1 예외). iOS=APNs, Android=FCM.
5. 출발일: 오늘 화면 상단 "출발일" 카드 — 집(출발 시각까지) + 목적지(도착 후) 시간별 동시 표시, 요약 알림에도 포함. 여행 기간 중 출근 브리핑·요약 일시중지 제안.
6. 어댑터 추가: 기상청 중기(예보구역 코드 매핑), Visual Crossing, Pirate Weather. 해외는 현지시각 표시.

### Phase 6 — 고도화
1. **정확도 기반 가중치**: `forecast_log` vs `obs_log`로 집·회사의 소스·계열별 Brier 점수(리드타임 구간별) → 가중치 자동 조정, 비교 화면에 "최근 30일 적중률".
2. Android 홈 위젯(Glance), iOS 홈 위젯 — 상시 "오늘 최대 강수확률".
3. 개인화: 출퇴근 시간대 가중 강조, 알림 문구·임계값 세분화.

---

## 4. 검증 방법
- **서버**: `deno test`(그리드 변환, 어댑터 픽스처, 종합 알고리즘, 주입 시계 기반 스케줄·DST·base_time, `dispatch_log` 중복 방지), `supabase start` + `functions serve` 로컬에서 `curl`로 `forecast`/`briefing` 확인, 실제 키로 서울 좌표 스모크 테스트, 야간 실 API 점검.
- **앱 공통**: `./gradlew :composeApp:allTests`(commonMain 단위 테스트), Compose UI 테스트(강조 배너·차트).
- **Android**: Robolectric로 스케줄 계산, 디버그 메뉴 "지금 출근 브리핑 테스트"(현재부터 3분 창), `adb shell dumpsys alarm`, `adb shell dumpsys deviceidle force-idle`, `adb shell am set-standby-bucket`으로 제약 상황 테스트, 갤럭시 실기기에서 잠금화면·Now Bar 확인.
- **iOS**: 이 클라우드 컨테이너(Linux)에서는 빌드 불가 → 사용자 Mac(Xcode) 또는 macOS CI에서 빌드, Apple Push Notifications Console + `server/scripts/send_la_push.ts`로 시작/업데이트/종료 테스트, 실기기 확인.
- **단계별 완료 기준**
  - Phase 1: 서울 좌표 종합 JSON(4개 계열) 정상, 로그 적재 확인
  - Phase 2: 양 플랫폼에서 지정 시각 ±1분 내 요약 알림 수신
  - Phase 3: T-60 잠금화면 표시 → 15분 갱신 → T에 사라짐, 비 예보 시 강조, 공휴일·건너뛰기 시 미표시
  - Phase 4: 6개 이상 소스 비교 화면, 한도 초과 없음
  - Phase 5: 여행 변화 추이 누적, 변화 알림 수신, 출발일 카드 표시
