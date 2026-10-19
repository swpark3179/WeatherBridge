# 계정·키 설정

비밀값은 저장소나 앱에 넣지 않습니다. GitHub Actions secrets, Supabase 함수 시크릿, Supabase Vault에만 둡니다.

## 비밀값 한눈에 보기

| 이름 | 등록 위치 | 용도 | 상태 |
|---|---|---|---|
| `SUPABASE_PROJECT_ID` | Actions, Codespaces | 배포·점검 워크플로가 프로젝트를 찾을 때 | 등록됨 |
| `SUPABASE_REGION` | Actions, Codespaces | `Server smoke`가 함수를 이 리전에서 실행하도록 지정 (`ap-northeast-2`) | 등록됨 |
| `SPIKE_TOKEN` | Actions, Codespaces, Supabase 함수 시크릿, Vault(`spike_token`) | 운영 토큰. `refresh`·`forecast`·`briefing`·스파이크 함수 호출 시 `x-spike-token` 헤더 | 등록됨 (Vault는 아래 3번에서 1회 등록) |
| `SUPABASE_API_KEY` | Actions, Codespaces | Publishable key. Phase 2 앱 접속용 | 등록됨 |
| `SUPABASE_ANON_KEY` | Actions, Codespaces | Legacy anon key. 예비 (신규 코드에서는 사용 안 함) | 등록됨 |
| `SUPABASE_ACCESS_TOKEN` | Actions | 배포 워크플로의 Supabase CLI 인증 | **추가 필요** |
| `SUPABASE_DB_PASSWORD` | Actions | 배포 워크플로의 마이그레이션 적용 | **추가 필요** |
| `KMA_SERVICE_KEY` | Actions (배포 때 함수 시크릿으로 자동 동기화) | 기상청 API | 선택 (키 발급 후) |
| `project_url` | Vault | cron이 `refresh`를 호출할 주소 | 아래 3번에서 1회 등록 |
| `APNS_*` | Supabase 함수 시크릿 | APNs 발송 | Apple Developer 가입 후 |

- Supabase 함수 시크릿 이름은 `SUPABASE_`로 시작할 수 없습니다(예약어).
- `SPIKE_TOKEN`을 바꿀 때는 Actions·Codespaces·Vault를 모두 같은 값으로 바꾸고 배포 워크플로를 다시 실행합니다. 함수 시크릿은 배포 때 Actions 값으로 덮어씁니다.

## Phase 1 서버 준비 (1회)

### 1. Actions secrets 추가
저장소 **Settings → Secrets and variables → Actions → New repository secret**
- `SUPABASE_ACCESS_TOKEN`: Supabase 대시보드 → 계정 메뉴 → **Access Tokens** → 새 토큰 생성. 권한을 고르는 화면이 나오면 이 프로젝트의 Edge Functions 배포, 시크릿, 데이터베이스 마이그레이션이 가능하도록 선택합니다.
- `SUPABASE_DB_PASSWORD`: 프로젝트를 만들 때 정한 DB 비밀번호. 잊었다면 Project Settings → Database에서 재설정합니다(Edge Functions는 DB 비밀번호를 쓰지 않아 영향 없음).
  - 재설정한 비밀번호는 커넥션 풀러에 몇 분 뒤 반영됩니다. 그 전에 배포하면 `Apply migrations`가 `password authentication failed (28P01)`로 실패하니, 3~5분 뒤 다시 실행합니다.
- (선택) `KMA_SERVICE_KEY`: 아래 "기상청 API 키"의 Decoding 키.

### 2. 배포
- `Server deploy` 워크플로가 마이그레이션 적용(테이블·cron) → 함수 시크릿 동기화 → 함수 배포를 합니다.
- main에 `server/supabase/**` 변경이 병합되면 자동 실행되고, Actions 탭에서 수동 실행도 됩니다.

### 3. SQL Editor에서 1회 실행 (첫 배포 후)
```sql
-- cron이 refresh를 호출할 때 쓰는 값
select vault.create_secret('https://<프로젝트ID>.supabase.co', 'project_url');
select vault.create_secret('<SPIKE_TOKEN 값>', 'spike_token');

-- 집·회사. 좌표는 소수 둘째 자리(약 1km)까지만 저장됩니다.
insert into public.places (kind, name, lat, lon) values
  ('home',   '집',   37.00, 127.00),
  ('office', '회사', 37.00, 127.00);
```
- 좌표 얻는 법: Google 지도에서 위치를 마우스 오른쪽 버튼으로 누르면 맨 위에 `37.5665, 126.9780` 형식으로 나오고, 누르면 복사됩니다.
- 이름(`집`, `회사`)은 브리핑·알림 문구에 그대로 쓰입니다.
- 위치 수정: `update public.places set lat = 37.00, lon = 127.00, kma_nx = null, kma_ny = null where kind = 'home';` (격자는 다음 수집 때 다시 계산)
- 토큰 변경: `select vault.update_secret((select id from vault.secrets where name = 'spike_token'), '<새 값>');`

### 4. 확인
- `Server smoke` 워크플로(수동 실행, 매일 07:17 KST 자동 실행)가 함수들을 호출해 결과를 요약합니다.
- SQL로 직접 확인할 때:
```sql
select jobname, schedule, active from cron.job;
select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
select provider, loc_key, issued_at from public.forecast_log order by id desc limit 10;
select * from public.obs_log order by obs_time desc limit 5;
```

## Phase 0에서 설정한 것 (참고)

### Supabase 프로젝트
- 별도 계정에 생성, 리전 서울(`ap-northeast-2`), 무료 플랜. 프로젝트 이름은 무엇이든 상관없습니다.
- `server/supabase/config.toml`의 `project_id`는 로컬 식별자일 뿐이라 실제 프로젝트 이름과 달라도 됩니다.
- 배포는 이제 GitHub Actions가 하지만, PC에서도 Supabase CLI로 할 수 있습니다(Node.js 필요). 모든 명령은 `server` 폴더에서 실행합니다.
  ```bash
  npx supabase login
  npx supabase link --project-ref <프로젝트ID>
  npx supabase db push
  npx supabase functions deploy   # Docker 오류가 나면 --use-api 추가
  ```

### 기상청 API 키 (data.go.kr)
1. [공공데이터포털](https://www.data.go.kr) 로그인
2. "기상청_단기예보 ((구)_동네예보) 조회서비스"(15084084) → **활용신청** (개발계정은 자동 승인, 일 10,000건). 단기예보와 초단기실황(관측)이 같은 서비스에 포함됩니다.
3. 마이페이지 → 활용 현황에서 **일반 인증키(Decoding)** 복사
4. Actions secret `KMA_SERVICE_KEY`로 등록 → 다음 배포 때 함수 시크릿으로 반영
5. 승인 직후에는 `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`가 날 수 있습니다(반영까지 1~2시간).

## Apple Developer 가입 후 (실기기 검증·배포)

### Apple Developer Program (연 US$99)
- 푸시 알림, Live Activity 원격 시작, WeatherKit, TestFlight 배포에 모두 필요합니다.
- Mac이 없으므로 서명·업로드는 GitHub Actions에서 합니다(Phase 2에서 파이프라인 구성).

### App ID
- Certificates, Identifiers & Profiles → Identifiers
  - `io.github.swpark3179.weatherbridge` — Capabilities: **Push Notifications**
  - `io.github.swpark3179.weatherbridge.CommuteWidget`
- `ios/project.yml`의 `DEVELOPMENT_TEAM`에 팀 ID 입력.

### APNs 인증 키 (.p8)
- Keys → 새 키 → **Apple Push Notifications service (APNs)** 체크 → 다운로드(한 번만 가능)
- Supabase 함수 시크릿 등록
  - `APNS_TEAM_ID`: 팀 ID (10자리)
  - `APNS_KEY_ID`: 키 ID (10자리)
  - `APNS_P8`: .p8 파일 내용 전체(`-----BEGIN PRIVATE KEY-----` 포함)
  - `APNS_BUNDLE_ID`: 기본값 `io.github.swpark3179.weatherbridge` (생략 가능)

### App Store Connect API 키 (CI 업로드용, Phase 2)
- App Store Connect → 사용자 및 액세스 → 통합 → API 키 생성 → GitHub 저장소 Secrets에 등록.

## 이후 단계에서 필요한 것
| 단계 | 항목 |
|---|---|
| Phase 3 | data.go.kr 한국천문연구원 특일정보(공휴일) 활용신청 |
| Phase 4 | WeatherKit(위 .p8 키에 WeatherKit 서비스 추가), Tomorrow.io, WeatherAPI.com, OpenWeatherMap 키 |
| Phase 5 | data.go.kr 기상청 중기예보 활용신청, Visual Crossing, Pirate Weather 키 |
