# 결정 기록

| # | 결정 | 이유 | 일자 |
|---|---|---|---|
| D1 | **iOS 전용**, Swift + SwiftUI 네이티브 | 사용자 결정(iOS만 개발). 핵심 기능(Live Activity·WidgetKit·APNs)이 모두 Swift API라 크로스플랫폼 계층이 불필요 | 2026-10-17 |
| D2 | 앱 ID `io.github.swpark3179.weatherbridge`, 위젯 확장 `…weatherbridge.CommuteWidget` | GitHub 계정 기반이라 충돌 없음. APNs 토픽·App ID에 연결되므로 변경 금지 | 2026-10-17 |
| D3 | iOS 최소 버전 **18.0** | Live Activity 브로드캐스트 채널(`input-push-channel`)이 18부터. 기기별 업데이트 토큰 없이도 갱신·종료 가능 | 2026-10-17 |
| D4 | Xcode 프로젝트는 **XcodeGen**(`ios/project.yml`)으로 생성, `.xcodeproj` 미커밋 | Mac 없이 텍스트로 프로젝트를 관리하고 CI에서 생성 | 2026-10-17 |
| D5 | 플랫폼 독립 로직은 **WeatherCore** Swift 패키지(Foundation만) | Linux CI에서 `swift test`로 빠르게 검증. 서버와의 데이터 계약을 픽스처로 공유 | 2026-10-17 |
| D6 | 빌드·검증은 **GitHub Actions** (server: Deno, core: Linux Swift, ios: macOS) | Mac 없음. 공개 저장소라 macOS 러너 무료 | 2026-10-17 |
| D7 | 실기기 배포는 **Apple Developer Program + CI 서명 + TestFlight** | Mac 없이 설치 가능한 유일한 경로. 푸시·Live Activity·WeatherKit에도 멤버십 필요 | 2026-10-17 |
| D8 | 서버는 **Supabase 서울 리전 무료 티어**, 푸시는 **APNs 직접**(Firebase 미사용) | iOS 전용이라 FCM 불필요. Edge Function(Deno)에서 HTTP/2로 APNs 호출 | 2026-10-17 |
| D9 | Live Activity 날짜 필드는 **epoch 초(Int)** | ActivityKit의 Date 디코딩 방식에 의존하지 않고 서버와 계약을 단순화 | 2026-10-17 |
| D10 | Supabase 프로젝트는 **별도 계정**(서울 리전)에 둔다 | 기존 계정이 무료 프로젝트 한도에 도달. 이 계정은 Claude의 Supabase 연결 밖이라 배포 절차를 문서화([setup.md](setup.md)) | 2026-10-18 |
| D11 | 서버 배포는 **GitHub Actions**(`server-deploy.yml`), 점검은 `server-smoke.yml`(매일 실행) | Claude가 워크플로를 실행해 배포·점검까지 할 수 있고, 매일 호출로 무료 프로젝트의 7일 무활동 일시정지도 막음 | 2026-10-18 |
| D12 | Phase 1 함수(`refresh`·`forecast`·`briefing`)는 **운영 토큰 `SPIKE_TOKEN`**으로 보호 | 앱 사용자가 아직 없음. Phase 2 앱용 함수는 Supabase 권장 방식(사용자 JWT, `@supabase/server`)으로 전환 | 2026-10-18 |
| D13 | 서버는 **새 API 키 체계**(`SUPABASE_SECRET_KEYS`, publishable key) 사용, legacy anon/service_role 키는 쓰지 않음 | legacy 키는 2026년 말 폐기 예정 | 2026-10-18 |
| D14 | TestFlight 빌드는 **배포 인증서 + App Store 프로파일로 수동 서명**, 프로파일은 App Store Connect API로 이름을 찾아 설치 (`iOS TestFlight` 워크플로) | 자동 서명은 등록 기기가 없으면 개발용 프로파일을 못 만들고, 임시 러너마다 인증서가 새로 생기며 Admin 키가 필요. 수동 서명은 매번 같은 인증서를 써서 안정적 | 2026-10-20 |
| D15 | 프로젝트 ref·publishable key는 **빌드할 때 빌드 설정으로 주입**(Info.plist `WBSupabase*`), `aps-environment`는 구성별(Debug development / Release production) | 공개 저장소에 접속 정보를 남기지 않음. TestFlight 앱은 production APNs를 쓰므로 서명 프로파일과 entitlement가 일치해야 함 | 2026-10-20 |
| D16 | 요약 알림은 **pg_cron이 매분 `dispatch`를 호출**하고, 보낼지 여부(현지 예정 시각·15분 창·하루 1회)는 함수(`schedule.ts`)가 판단 | 판단 로직을 SQL에 두면 테스트할 수 없음. 월 약 4.5만 회 호출로 무료 한도(50만) 안. Phase 3 출근 브리핑도 같은 경로를 씀 | 2026-10-20 |
| D17 | 앱의 쓰기는 **RPC(`set_place`, `register_device`, `delete_my_account`)**로만, 읽기는 RLS(본인 행). 운영 토큰 함수(`forecast`·`briefing`)는 `user_id`가 없는 운영자 장소만 쓴다 | 좌표 반올림·사용자당 집·회사 1곳·재설치 시 기기 이전을 서버에서 보장. 점검 결과가 앱 사용자 데이터에 흔들리지 않음 | 2026-10-20 |
| D18 | 재설치 대비 **복구 코드는 보류**. 세션은 키체인에 두고, 새 기기에서는 다시 온보딩 | 개인·지인용이라 집·회사 2곳을 다시 등록하는 비용이 작음. 필요해지면 RPC 한 쌍으로 추가 | 2026-10-20 |
| D19 | 앱의 서버 접속은 **URLSession 최소 클라이언트**(WeatherCore `AuthClient`·`SupabaseAPI`), 세션은 **키체인(이 기기에서만)** | supabase-swift 최신은 CI의 Xcode보다 새 도구가 필요하고 의존성이 큼. 갱신 토큰은 한 번만 쓸 수 있어 동시 갱신을 한 번으로 묶고, 새 토큰을 먼저 저장. Linux CI에서 가짜 전송 계층으로 테스트 | 2026-10-20 |
| D20 | 장소 검색은 **Apple 지도(MKLocalSearchCompleter)**, 현재 위치는 km 정확도 | Open-Meteo 지오코딩은 시·구·동 이름만 찾아 회사 주소·건물 검색이 안 됨. 키가 필요 없고 한국 주소를 지원 | 2026-10-20 |
