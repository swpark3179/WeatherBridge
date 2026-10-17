# WeatherBridge

집·회사 특화 **시간대별 강수확률** iOS 앱. 여러 무료 날씨 소스를 비교·종합하고, 출근 1시간 전부터 잠금화면(Live Activity)에 오늘 비 소식을 보여줍니다.

- 구현 계획: [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md)
- 결정 기록: [docs/decisions.md](docs/decisions.md)
- 계정·키 설정: [docs/setup.md](docs/setup.md)
- 기술 검증(Phase 0): [docs/spikes.md](docs/spikes.md)

## 구조
```
ios/        SwiftUI 앱 + CommuteWidget(Live Activity) + WeatherCore 패키지 (XcodeGen)
server/     Supabase Edge Functions (Deno/TypeScript)
docs/       계획·결정·설정 문서
```

## 빌드·테스트
```bash
# 서버
cd server && deno task fmt:check && deno task lint && deno task check && deno task test

# WeatherCore (macOS 또는 Linux)
cd ios/Packages/WeatherCore && swift test

# iOS 앱 (macOS + Xcode)
brew install xcodegen
cd ios && xcodegen generate && open WeatherBridge.xcodeproj
```
Mac이 없으면 GitHub Actions(`.github/workflows/ci.yml`)가 위 과정을 모두 실행합니다.
