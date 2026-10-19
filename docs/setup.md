# 계정·키 설정

비밀값은 저장소나 앱에 넣지 않습니다. GitHub Actions secrets, Supabase 함수 시크릿, Supabase Vault에만 둡니다.

## 비밀값 한눈에 보기

| 이름 | 등록 위치 | 용도 | 상태 |
|---|---|---|---|
| `SUPABASE_PROJECT_ID` | Actions, Codespaces | 배포·점검 워크플로가 프로젝트를 찾을 때 | 등록됨 |
| `SUPABASE_REGION` | Actions, Codespaces | `Server smoke`가 함수를 이 리전에서 실행하도록 지정 (`ap-northeast-2`) | 등록됨 |
| `SPIKE_TOKEN` | Actions, Codespaces, Supabase 함수 시크릿, Vault(`spike_token`) | 운영 토큰. `refresh`·`forecast`·`briefing`·스파이크 함수 호출 시 `x-spike-token` 헤더 | 등록됨 (Vault는 아래 3번에서 1회 등록) |
| `SUPABASE_API_KEY` | Actions, Codespaces | Publishable key. `iOS TestFlight`가 앱에 넣는다 (`sb_publishable_…`만 허용) | 등록됨 |
| `SUPABASE_ANON_KEY` | Actions, Codespaces | Legacy anon key. 예비 (신규 코드에서는 사용 안 함) | 등록됨 |
| `SUPABASE_ACCESS_TOKEN` | Actions | 배포 워크플로의 Supabase CLI 인증 | 등록됨 |
| `SUPABASE_DB_PASSWORD` | Actions | 배포 워크플로의 마이그레이션 적용 | 등록됨 |
| `KMA_SERVICE_KEY` | Actions (배포 때 함수 시크릿으로 자동 동기화) | 기상청 API | 등록됨 |
| `project_url` | Vault | cron이 `refresh`를 호출할 주소 | 등록됨 |
| `APPLE_TEAM_ID` | Actions (배포 때 함수 시크릿 `APNS_TEAM_ID`로 동기화) | 팀 ID(10자리). 앱 서명·APNs | 등록됨 |
| `APNS_KEY_ID`, `APNS_P8` | Actions (배포 때 함수 시크릿으로 동기화) | APNs 인증 키 ID와 .p8 내용 | 등록됨 |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | Actions | App Store Connect API 키. 프로파일 조회·TestFlight 업로드 | 등록됨 |
| `IOS_DIST_P12_B64`, `IOS_DIST_P12_PASSWORD` | Actions | Apple Distribution 인증서(.p12, base64)와 비밀번호 | **추가 필요** (아래 "TestFlight 배포") |

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

## TestFlight 배포 (Phase 2, 1회 준비)

Mac이 없으므로 서명·업로드는 `iOS TestFlight` 워크플로가 합니다. 배포 인증서와 App Store 프로파일로 **수동 서명**합니다.
- 자동 서명은 쓰지 않습니다. 기기 등록이 필요하고, 실행할 때마다 인증서가 새로 생기며, Admin 키가 필요하기 때문입니다.
- 아래 순서대로 하세요. 프로파일은 App ID의 기능이 모두 정해진 뒤 마지막에 만듭니다. 나중에 기능을 바꾸면 프로파일을 다시 만들어야 합니다.

### 1. App ID 기능 확인
[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → Identifiers
- `io.github.swpark3179.weatherbridge`
  - **Push Notifications** 체크 → Configure(또는 Edit)에서 **Broadcast Capability**도 켭니다(Live Activity 채널 갱신에 필요).
  - Save
- `io.github.swpark3179.weatherbridge.CommuteWidget`: 추가 기능 없음
- Keys에서 APNs 키를 열어 환경이 **Sandbox & Production**인지 확인합니다. TestFlight 앱은 Production APNs를 씁니다.

### 2. 배포 인증서 (.p12)
Windows에서는 Git for Windows에 들어 있는 **Git Bash**를 엽니다. 맨 앞의 `MSYS_NO_PATHCONV=1`은 Git Bash가 `/CN=…`을 파일 경로로 바꾸지 않게 합니다.
```bash
mkdir -p ~/wb-cert && cd ~/wb-cert
openssl genrsa -out dist.key 2048
MSYS_NO_PATHCONV=1 openssl req -new -key dist.key -out dist.csr -subj "/CN=WeatherBridge Distribution/C=KR"
```
1. Certificates → **+** → **Apple Distribution** → Continue → `dist.csr` 업로드 → 내려받은 `distribution.cer`을 `~/wb-cert`에 둡니다.
2. 인증서와 키를 .p12로 묶습니다. 비밀번호를 물어보면 새로 정해 입력합니다(이 값이 `IOS_DIST_P12_PASSWORD`).
   ```bash
   openssl x509 -inform DER -in distribution.cer -out dist.pem
   openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12
   ```
   - `-legacy` 오류가 나면 이것으로 바꿉니다: `openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -inkey dist.key -in dist.pem -out dist.p12`
   - 최신 OpenSSL 기본 암호화로 만든 .p12는 macOS 키체인이 읽지 못해서, 예전 방식으로 묶습니다.
3. base64로 바꿔 클립보드에 복사합니다.
   ```bash
   base64 -w0 dist.p12 | clip
   ```
4. GitHub → Settings → Secrets and variables → Actions에 등록합니다.
   - `IOS_DIST_P12_B64`: 복사한 내용
   - `IOS_DIST_P12_PASSWORD`: 2번에서 정한 비밀번호
5. `~/wb-cert` 폴더(특히 `dist.key`)는 안전한 곳에 백업하거나 지웁니다. 인증서를 다시 만들 때는 같은 절차를 반복하면 됩니다.

### 3. App Store 프로파일 2개
Profiles → **+** → Distribution의 **App Store Connect** → Continue
| App ID | 인증서 | 프로파일 이름(정확히) |
|---|---|---|
| `io.github.swpark3179.weatherbridge` | 2번에서 만든 Apple Distribution | `WeatherBridge AppStore` |
| `io.github.swpark3179.weatherbridge.CommuteWidget` | 같은 인증서 | `WeatherBridge Widget AppStore` |
- 워크플로가 App Store Connect API로 이 이름의 프로파일을 찾아 설치하므로, 내려받을 필요는 없습니다.
- 이름이 다르면 `ios/project.yml`과 `.github/workflows/ios-testflight.yml`도 같이 바꿔야 합니다.

### 4. App Store Connect
- API 키(`ASC_*`)의 역할은 **App Manager 이상**이어야 합니다(프로파일 조회·업로드).
- 앱 → **TestFlight** → 내부 테스트 → 그룹을 만들고 본인 계정을 추가합니다.
- iPhone에 **TestFlight** 앱을 설치하고 같은 Apple 계정으로 로그인합니다.

### 5. 실행
- Actions → **iOS TestFlight** → Run workflow. 빌드 번호는 `실행 번호.시도 번호`로 자동으로 정해집니다.
- 업로드 후 App Store Connect 처리(수 분~30분)가 끝나면 TestFlight 앱에 나타납니다.
- 암호화 수출 규정 질문은 `ITSAppUsesNonExemptEncryption=false`로 건너뜁니다.

### APNs 인증 키 (.p8)
- 함수 시크릿 `APNS_TEAM_ID`·`APNS_KEY_ID`·`APNS_P8`은 `Server deploy`가 Actions의 `APPLE_TEAM_ID`·`APNS_KEY_ID`·`APNS_P8`로 자동 등록합니다.
- .p8은 줄바꿈을 뺀 한 줄로 등록되며, 함수가 그대로 읽습니다.
- `APNS_BUNDLE_ID`는 기본값 `io.github.swpark3179.weatherbridge`를 씁니다.

## 이후 단계에서 필요한 것
| 단계 | 항목 |
|---|---|
| Phase 3 | data.go.kr 한국천문연구원 특일정보(공휴일) 활용신청 |
| Phase 4 | WeatherKit(위 .p8 키에 WeatherKit 서비스 추가), Tomorrow.io, WeatherAPI.com, OpenWeatherMap 키 |
| Phase 5 | data.go.kr 기상청 중기예보 활용신청, Visual Crossing, Pirate Weather 키 |
