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
| D10 | Supabase 프로젝트는 **별도 계정**(서울 리전)에 두고, 배포·시크릿은 **사용자 PC의 Supabase CLI**로 수행 | 기존 계정이 무료 프로젝트 한도에 도달. 이 계정은 Claude의 Supabase 연결 밖이라 배포 절차를 문서화([setup.md](setup.md)) | 2026-10-18 |
