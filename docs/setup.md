# 계정·키 설정

비밀값은 저장소나 앱에 넣지 않고 **Supabase Edge Function 시크릿**에만 등록합니다.
(Supabase 대시보드 → 프로젝트 → Edge Functions → Secrets)

## 지금 필요한 것 (Phase 0)

### 1. Supabase 프로젝트
- 별도 계정에 생성됨, 리전 서울(`ap-northeast-2`), 무료 플랜. 프로젝트 이름은 무엇이든 상관없습니다.
- `server/supabase/config.toml`의 `project_id`는 로컬 식별자일 뿐이라 실제 프로젝트 이름과 달라도 됩니다.
- 배포는 PC에서 Supabase CLI로 합니다(Node.js 필요, Mac 불필요). 모든 명령은 `server` 폴더에서 실행합니다.
  ```bash
  npx supabase login                          # 프로젝트가 있는 계정으로 로그인
  npx supabase link --project-ref <프로젝트ID>   # 대시보드 Project Settings → General의 ID
  npx supabase secrets set SPIKE_TOKEN=<임의의 긴 문자열>
  npx supabase functions deploy spike-reach --no-verify-jwt
  npx supabase functions deploy spike-apns --no-verify-jwt
  # Docker 오류가 나면 위 deploy 명령 끝에 --use-api 추가
  ```
- 확장 기능(`supabase/migrations/20261017000000_extensions.sql`)은 대시보드 **SQL Editor**에서 실행합니다.
  ```sql
  create extension if not exists pg_net with schema extensions;
  create extension if not exists pg_cron;
  ```
- 측정 방법은 [spikes.md](spikes.md) S1 (Windows PowerShell 명령 포함).

### 2. 기상청 단기예보 API 키 (data.go.kr)
1. [공공데이터포털](https://www.data.go.kr) 로그인
2. "기상청_단기예보 ((구)_동네예보) 조회서비스"(15084084) → **활용신청** (개발계정은 자동 승인, 일 10,000건)
3. 마이페이지 → 활용 현황에서 **일반 인증키(Decoding)** 복사
4. Supabase 시크릿 `KMA_SERVICE_KEY`에 등록 (`npx supabase secrets set KMA_SERVICE_KEY=<디코딩 키>`)
5. 승인 직후에는 `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`가 날 수 있습니다(반영까지 1~2시간).

### 3. 스파이크 함수 보호 토큰
- 시크릿 `SPIKE_TOKEN`: 임의의 긴 문자열. 스파이크 함수 호출 시 `x-spike-token` 헤더로 보냅니다.

## Apple Developer 가입 후 (실기기 검증·배포)

### 4. Apple Developer Program (연 US$99)
- 푸시 알림, Live Activity 원격 시작, WeatherKit, TestFlight 배포에 모두 필요합니다.
- Mac이 없으므로 서명·업로드는 GitHub Actions에서 합니다(Phase 2에서 파이프라인 구성).

### 5. App ID
- Certificates, Identifiers & Profiles → Identifiers
  - `io.github.swpark3179.weatherbridge` — Capabilities: **Push Notifications**
  - `io.github.swpark3179.weatherbridge.CommuteWidget`
- `ios/project.yml`의 `DEVELOPMENT_TEAM`에 팀 ID 입력.

### 6. APNs 인증 키 (.p8)
- Keys → 새 키 → **Apple Push Notifications service (APNs)** 체크 → 다운로드(한 번만 가능)
- Supabase 시크릿 등록
  - `APNS_TEAM_ID`: 팀 ID (10자리)
  - `APNS_KEY_ID`: 키 ID (10자리)
  - `APNS_P8`: .p8 파일 내용 전체(`-----BEGIN PRIVATE KEY-----` 포함)
  - `APNS_BUNDLE_ID`: 기본값 `io.github.swpark3179.weatherbridge` (생략 가능)

### 7. App Store Connect API 키 (CI 업로드용, Phase 2)
- App Store Connect → 사용자 및 액세스 → 통합 → API 키 생성 → GitHub 저장소 Secrets에 등록.

## 이후 단계에서 필요한 것
| 단계 | 항목 |
|---|---|
| Phase 3 | data.go.kr 한국천문연구원 특일정보(공휴일) 활용신청 |
| Phase 4 | WeatherKit(위 .p8 키에 WeatherKit 서비스 추가), Tomorrow.io, WeatherAPI.com, OpenWeatherMap 키 |
| Phase 5 | data.go.kr 기상청 중기예보 활용신청, Visual Crossing, Pirate Weather 키 |
