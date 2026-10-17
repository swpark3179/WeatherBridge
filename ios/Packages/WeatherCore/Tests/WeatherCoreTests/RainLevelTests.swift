import Testing
@testable import WeatherCore

@Suite struct RainLevelTests {
    @Test(arguments: [
        (0, RainLevel.clear), (19, .clear),
        (20, .low), (39, .low),
        (40, .moderate), (59, .moderate),
        (60, .high), (100, .high),
    ])
    func boundaries(pop: Int, expected: RainLevel) {
        #expect(RainLevel(pop: pop) == expected)
    }

    @Test func ordering() {
        #expect(RainLevel.clear < .low)
        #expect(RainLevel.moderate < .high)
        #expect(RainLevel.allCases.max() == .high)
    }
}
