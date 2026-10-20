# WeatherBridge — 단계적 구현 계획 (iOS)

## Context
- 목표: **내 지역(집·회사) 특화 날씨**, 특히 **시간대별 강수확률**을 여러 무료 날씨 소스로 비교·종합.
- 핵심 기능
  1. 출근시간 T 기준 **T-60분 ~ T 동안 잠금화면 브리핑**(Live Activity). 오늘 집·회사 중 비 올 가능성이 있는 시간대가 있으면 강조.
  2. 지정 시각에 **집·회사 오늘 날씨 요약 알림**.
  3. **여행 모드**: 기간·지역(국내/해외)을 등록하면 출발 전까지 예보 변화를 계속 추적. 출발일에는 집 날씨도 함께.
  4. **다중 무료 날씨 소스 비교·종합**(시간대별 강수확률 중심).
- 결정사항: **iOS 전용** / 경량 서버 / 여행지 국내+해외 / 개인·지인용 배포(스토어 공개 X) / 앱 ID `io.github.swpark3179.weatherbridge`.
- 개발 환경: Mac 없음 → iOS 빌드·검증은 GitHub Actions macOS 러너, 실기기 설치는 Apple Developer 가입 후 CI 서명 + TestFlight. 세부 결정은 [decisions.md](decisions.md).

---

## 1. 기술 선택

### 앱: Swift + SwiftUI (네이티브)
- iOS 전용이므로 크로스플랫폼 계층이 주는 이점이 없고, 핵심 기능(Live Activity·WidgetKit·ActivityKit·APNs)이 모두 Swift 전용 API.
- 구성
  - **앱 타깃**: SwiftUI 화면, APNs 등록, Live Activity 토큰 관리
  - **CommuteWidget 확장**: Live Activity 잠금화면/Dynamic Island UI, (Phase 3) 잠금화면 위젯
  - **WeatherCore 패키지**: 플랫폼 독립 로직(데이터 계약, 강수 등급 등). Foundation만 사용해 Linux에서도 `swift test`
- 프로젝트 파일은 **XcodeGen**(`ios/project.yml`)으로 생성 → Mac 없이도 텍스트로 관리, CI에서 생성·빌드.

### 서버: Supabase (무료 티어, 서울 리전)
- Postgres + Edge Functions(Deno/TypeScript) + `pg_cron`/`pg_net` + 익명 인증 + RLS.
- 역할
  - **모든 날씨 API 키 보관**(Edge secret; 앱에 포함 X)
  - **예보 수집·정규화·종합의 유일한 구현** + 캐시 → 앱 화면·푸시가 같은 결과 사용
  - **모든 스케줄링과 푸시**: iOS는 정해진 시각의 백그라운드 실행이 보장되지 않으므로 서버가 시각에 맞춰 **APNs로 직접 발송**(요약 알림, Live Activity 시작/갱신/종료, 여행 변화 알림). Firebase 미사용.

### 날씨 소스 (2026-10 무료 조건 확인)
| 소스 | 강수확률 필드 | 무료 범위 | 해상도 | 용도 |
|---|---|---|---|---|
| 기상청 단기예보 `getVilageFcst` | `POP` % | ~3~4일 | 1시간(연장구간 3시간 가능) | 국내 기준(가중치↑) |
| 기상청 중기예보 `getMidLandFcst` | `rnSt` | 4~10일 | 오전/오후·일 | 국내 여행 |
| Open-Meteo (키 없음, 비상업 1만/일) | 모델별 `precipitation_probability` | 16일 | 1시간 | ECMWF·GFS·ICON 3개 계열 비교, 해외, 폴백 |
| Apple WeatherKit REST | `precipitationChance` | ~10일 | 1시간 | 독자 블렌드(애플 개발자 멤버십 필요 — 어차피 필요) |
| Tomorrow.io (500/일) | `precipitationProbability` | ~5일 | 1시간 | 비교 |
| WeatherAPI.com | `chance_of_rain` | 3일 | 1시간 | 비교 |
| OpenWeatherMap 5day/3h | `pop`(0~1) | 5일 | 3시간 블록 | 비교(구간 단위) |
| Visual Crossing (1000건/일) | `precipprob` | 15일 | 1시간 | 여행(원거리) |
| Pirate Weather (1만/월) | `precipProbability` | 7일 | 1시간 | 해외(북미) |
- 제외: Google Weather(한국 예보 미지원), AccuWeather(무료 종료), MET Norway(한국 강수확률 없음), Open-Meteo의 KMA 모델(2026-03 이후 갱신 중단·POP 없음).
- Open-Meteo 모델 ID: `ecmwf_ifs025`, `ncep_gfs_seamless`, `dwd_icon_seamless`.
- 해외 지점은 기상청 소스 자동 제외. data.go.kr 장애(2025-09~10 전례) 대비 KMA API Hub를 보조 엔드포인트로 검토.

---

## 2. 전체 구조

```
WeatherBridge/
├─ ios/
│  ├─ project.yml              XcodeGen 정의 (앱 + CommuteWidget, iOS 18)
│  ├─ WeatherBridge/           앱: SwiftUI 화면, AppDelegate(APNs), Live Activity 브리지
│  ├─ CommuteWidget/           위젯 확장: Live Activity UI, (Phase 3) 잠금화면 위젯
│  ├─ Shared/                  앱·확장 공용 (ActivityAttributes 적합성, 강수 스타일)
│  └─ Packages/WeatherCore/    데이터 계약·도메인 로직 (Linux swift test)
├─ server/
│  ├─ deno.json
│  └─ supabase/
│     ├─ migrations/           스키마, RLS, pg_cron 잡
│     └─ functions/
│        ├─ _shared/providers/ kma.ts(단기예보·실황), open_meteo.ts, (이후) weatherkit.ts, ...
│        ├─ _shared/           apns.ts, kma_time.ts, kma_grid.ts, forecast_types.ts, aggregate.ts,
│        │                     briefing.ts, forecast_service.ts, db.ts, (이후) schedule.ts, quota.ts
│        ├─ refresh/           cron: 등록 위치별 예보 수집 → forecast_cache, 예보·관측 로그
│        ├─ forecast/          장소별 종합 예보 (캐시만 읽음)
│        ├─ briefing/          요약/출근 카드 가공
│        ├─ dispatch/          cron 5분: 요약 알림·Live Activity 수명주기 발송
│        └─ trip-watch/        여행 스냅샷·변화 감지·알림
├─ docs/
└─ .github/workflows/
   ├─ ci.yml                   server(Deno) / core(swift test, Linux) / ios(xcodebuild, macOS)
   ├─ server-deploy.yml        마이그레이션 + 함수 시크릿 동기화 + 함수 배포
   └─ server-smoke.yml         배포된 함수 점검 (매일 실행, 무료 프로젝트 일시정지 방지)
```

### 데이터 계약
- Live Activity 페이로드(`CommuteActivityAttributes`, `CommuteState`)는 `WeatherCore`에 정의하고, 서버 `apns.ts`가 같은 키로 생성.
- 계약 샘플 `ios/Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/live_activity_start.json`을 **서버 테스트(생성 결과와 일치)와 Swift 테스트(디코딩 가능)가 함께 검증**.
- 앱 `today` 응답(`TodayResponse`)도 같은 방식: `Fixtures/today_response.json` (서버에서 `deno task fixtures`로 다시 만든다).
- 날짜는 epoch 초(Int)로 주고받음.

### 주요 테이블
- `places`: kind(home/office/trip), lat/lon(약 1km로 스냅해 저장), IANA tz, kma_nx/ny, kma_mid_region
- `schedules`: 출근시간(현지시각)+tz, 요일별 on/off, 요약 시각, 공휴일 건너뛰기, "오늘 건너뛰기/휴가" 기간
- `trips`: place, 시작/종료일(목적지 기준), 출발 시각
- `devices`: apns_token, **apns_env**(sandbox/production), push-to-start 토큰, 브로드캐스트 채널 ID, 마지막 확인 시각
- `forecast_cache`, `forecast_log`(소스별 예보 기록), `obs_log`(기상청 실황 RN1/PTY), `trip_snapshots`, `dispatch_log`(unique: user, kind, local_date), `quota_ledger`

### 서버 운영 원칙
- **수집과 발송 분리**: `refresh`가 캐시를 채우고(기상청은 발표시각+15분, 그 외 1시간), `briefing`/`dispatch`는 캐시만 읽음 → Edge Function CPU 2초/150초 제한 회피. 각 소스는 개별 타임아웃 + `Promise.allSettled`.
- pg_cron → Edge 호출: Vault의 비밀값을 커스텀 헤더로 전달, 함수는 `verify_jwt=false` 배포, 즉시 202 반환 후 `EdgeRuntime.waitUntil`로 처리.
- **APNs**: 토큰 인증(.p8) JWT를 50분간 재사용(20~60분 규칙), 콜드 스타트 대비 DB에 저장.
- **무료 한도 장부**(`quota.ts`): Tomorrow 500/일, Visual Crossing 1000/일, Pirate 1만/월 초과 방지.
- **일시정지 방지**: GitHub Actions 일일 keep-alive 호출 + `dispatch` 마지막 실행 시각을 앱이 확인해 이상 시 경고 배너.
- 시간: 예보 시각은 UTC 저장·지점 tz로 표시, 기상청 base_time은 고정 +09:00로 계산하고 미발표 시 직전 발표 사용, 일정은 현지시각+IANA tz(DST 23/25시간 날 처리).

### 강수확률 종합 알고리즘 (`aggregate.ts`)
1. **정규화**: % 단위, UTC 정시 시작 슬롯. Open-Meteo "직전 1시간" 라벨 보정(관측값으로 검증 후 확정).
2. **구간 확률 분리**: OWM 3시간·기상청 연장 3시간·중기 오전/오후 값은 "구간 확률"이라 시간별 값에 복사하지 않음 → 시간별 종합에는 1시간 해상도 소스만, 구간 소스는 "비 구간/반나절" 단위 종합에만 사용.
3. **계열 묶기**(상관 소스 중복 방지): KMA / ECMWF계(Open-Meteo IFS, Pirate) / NCEP계(GFS) / DWD계(ICON) / 독자 블렌드(WeatherKit, Tomorrow, WeatherAPI, VC). 계열 내 평균 → 계열 간 가중 평균(국내 KMA 1.5, 기타 1.0).
4. **예보 범위별 고정 소스 세트**: 범위 경계에서 참여 소스가 바뀌어 그래프가 튀는 것을 방지(구간 경계 표시).
5. 시간별 출력: 종합 확률, 최소~최대, 합의도("6개 계열 중 4개 ≥ 임계값"), 참여 소스 수.
6. **등급**: 없음 <20 / 낮음 20–39 / 보통 40–59 / 높음 ≥60 (`WeatherCore.RainLevel`). 편차 ≥40%p면 "소스 간 의견 갈림".
7. **강조 규칙**: 오늘 남은 시간 중 집 또는 회사에서 `종합 ≥ 임계값(기본 30%, 설정 가능)` 또는 `기상청 ≥ 60%` 또는 `2개 이상 계열 ≥ 60%` → 강조. 연속 시간을 묶어 "☔ 회사 15–18시 최대 70% (5개 계열 중 4개)"로 문장화.

---

## 3. 단계별 구현 계획

### Phase 0 — 준비 + 기술 검증(스파이크) ← 완료 (실기기 S2·S3은 개발자 계정 가입 후)
1. 저장소 골격: XcodeGen 프로젝트(앱 + CommuteWidget, iOS 18), WeatherCore 패키지, `server/` Deno 프로젝트, CI 3개 잡.
2. iOS 실험실 화면: APNs·push-to-start 토큰 표시, 샘플 Live Activity 로컬 시작/채널 구독 시작/종료.
3. 서버 스파이크 함수: `spike-reach`(Edge → Open-Meteo·data.go.kr 접근성), `spike-apns`(채널 생성 → push-to-start → 채널 업데이트 → 종료).
4. 실기기 검증(개발자 계정 필요): push-to-start + `input-push-channel` → 채널 업데이트 → `end` + `stale-date`로 T에 확실히 사라지는지.
5. 절차·결과 기록: [spikes.md](spikes.md), 계정·키: [setup.md](setup.md).

### Phase 1 — 서버 예보 엔진 (기상청 + Open-Meteo) ← 완료(2026-10-20)
- 실서버 확인: 집·회사 모두 4개 계열 종합, 매시 20분 cron 수집, 예보·실황 기록 적재([spikes.md](spikes.md) "Phase 1 실서버 점검").
- 배포는 GitHub Actions(`server-deploy`), 점검은 `server-smoke`. 함수는 운영 토큰(`SPIKE_TOKEN`)으로 보호하고 Phase 2에서 사용자 인증으로 전환([decisions.md](decisions.md) D11–D13).
- 집·회사는 사용자가 SQL로 등록([setup.md](setup.md) "Phase 1 서버 준비").
1. `kma_grid.ts`(위경도→nx/ny Lambert 변환), base_time 계산(Phase 0의 `kma_time.ts` 확장).
2. 어댑터: **기상청 단기 + Open-Meteo(ECMWF/GFS/ICON 모델별)** → 첫날부터 4개 독립 계열 비교 가능. 어댑터는 `HourSlot[]` + 메타(발표시각, 범위, 해상도) 반환.
3. `refresh` cron + `forecast_cache`, `forecast`/`briefing` 함수, `aggregate.ts`.
4. **예보·관측 로그 적재 시작**(`forecast_log`, 기상청 초단기실황 RN1/PTY → `obs_log`) — Phase 6 정확도 가중치에 수개월 데이터 필요.
5. 테스트: 그리드 변환 기준값(서울시청 → 60,127), 어댑터 픽스처 정규화, 종합(계열 묶기·누락 소스·구간 확률), 주입 시계로 base_time 경계.

### Phase 2 — 앱 MVP + 지정 시각 요약 알림 ← 진행 중
- 진행 순서: A 배포 파이프라인(TestFlight) → B 서버(사용자·기기·`today`·`dispatch`) → C1 앱 로그인·온보딩·설정·알림 → C2 오늘·비교 화면.
- 진행 상황: A(#6)·B(#7) 병합·배포 완료(실서버 익명 흐름 확인). C1 진행 중.
1. 익명 로그인 + 기기 등록(APNs 토큰·apns_env, 재설치 대비 복구 코드), 온보딩: 집·회사 위치(현재 위치 / Open-Meteo Geocoding `language=ko` 검색).
2. **오늘 화면**: 집·회사 카드 — 시간대별 강수확률 막대(등급 색), 비 구간 강조 배너, 기온·하늘 보조, 갱신 시각.
3. **비교 화면(기본)**: 소스×시간 히트맵, 종합·편차·합의도.
4. 설정: 출근시간·요일, 요약 시각, 강수 임계값, 데이터 출처 표기(Open-Meteo CC BY, WeatherKit 로고·법적 링크 등).
5. **요약 알림**: `dispatch`가 요약 시각에 APNs 알림(서버 생성 문구) 발송, `dispatch_log`로 중복 방지.
6. 배포: CI 서명 + TestFlight 업로드 파이프라인(개발자 계정 필요), 앱 아이콘.

### Phase 3 — 출근 시간 잠금화면 브리핑
1. 공통: 공휴일(특일정보 월 1회 갱신 + 내장 폴백 목록), 요일별 on/off, "오늘 건너뛰기/휴가" 토글 → 요약·출근 브리핑 모두 적용.
2. `dispatch`: T-60 push-to-start(알림 포함, `input-push-channel`, `stale-date`=T) → 내용이 바뀔 때만 채널로 업데이트(priority 5) → T에 `end`(priority 10). 페이로드 4KB 이내.
3. 사용자별 브로드캐스트 채널(최근 1건 저장 정책) 생성·보관. 앱 실행 시 T가 지난 활동은 즉시 종료(Phase 0에 구현됨).
4. **폴백**: 잠금화면 위젯(WidgetKit 시간대별 타임라인 엔트리로 T-60~T에만 상세 표시) + time-sensitive 알림.
5. 강조 판단은 서버 `aggregate.ts` 결과 그대로 사용.

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
4. 변화 알림: 계열별로 감지, **등급이 바뀌고 ±20%p 이상 변화가 2회 연속**일 때만 APNs 발송, 여행당 하루 1회(D-1 예외).
5. 출발일: 오늘 화면 상단 "출발일" 카드 — 집(출발 시각까지) + 목적지(도착 후) 시간별 동시 표시, 요약 알림에도 포함. 여행 기간 중 출근 브리핑·요약 일시중지 제안.
6. 어댑터 추가: 기상청 중기(예보구역 코드 매핑), Visual Crossing, Pirate Weather. 해외는 현지시각 표시.

### Phase 6 — 고도화
1. **정확도 기반 가중치**: `forecast_log` vs `obs_log`로 집·회사의 소스·계열별 Brier 점수(리드타임 구간별) → 가중치 자동 조정, 비교 화면에 "최근 30일 적중률".
2. 홈 화면 위젯 — 상시 "오늘 최대 강수확률".
3. 개인화: 출퇴근 시간대 가중 강조, 알림 문구·임계값 세분화.

---

## 4. 검증 방법
- **서버**: `deno task test`(apns 페이로드·JWT, kma 시간, 어댑터 픽스처, 종합 알고리즘, 주입 시계 기반 스케줄, 중복 발송 방지), Supabase 배포 후 `pg_net` 또는 curl로 함수 호출, 야간 실 API 점검.
- **WeatherCore**: `swift test`(Linux CI, 계약 픽스처 디코딩 포함).
- **iOS 앱**: CI(macOS)에서 XcodeGen 생성 + 시뮬레이터 빌드. 실기기는 TestFlight 빌드로 확인.
- **단계별 완료 기준**
  - Phase 0: CI 3개 잡 녹색, 서버 스파이크 결과 기록, (개발자 계정 후) Live Activity 원격 시작→갱신→종료 확인
  - Phase 1: 서울 좌표 종합 JSON(4개 계열) 정상, 로그 적재 확인
  - Phase 2: 지정 시각 ±1분 내 요약 알림 수신
  - Phase 3: T-60 잠금화면 표시 → 갱신 → T에 사라짐, 비 예보 시 강조, 공휴일·건너뛰기 시 미표시
  - Phase 4: 6개 이상 소스 비교 화면, 한도 초과 없음
  - Phase 5: 여행 변화 추이 누적, 변화 알림 수신, 출발일 카드 표시
