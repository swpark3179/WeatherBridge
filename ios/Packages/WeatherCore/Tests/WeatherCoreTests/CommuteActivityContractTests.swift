import Foundation
import Testing
@testable import WeatherCore

/// 서버가 보내는 push-to-start 페이로드(계약 샘플)를 앱 모델로 디코딩할 수 있는지 확인한다.
/// 같은 파일을 server/tests/apns_test.ts가 서버 빌더 출력과 비교한다.
@Suite struct CommuteActivityContractTests {
    private struct Envelope: Decodable {
        struct APS: Decodable {
            let event: String
            let attributesType: String
            let attributes: CommuteActivityAttributes
            let contentState: CommuteState
            let staleDate: Int
            let inputPushChannel: String

            enum CodingKeys: String, CodingKey {
                case event
                case attributesType = "attributes-type"
                case attributes
                case contentState = "content-state"
                case staleDate = "stale-date"
                case inputPushChannel = "input-push-channel"
            }
        }
        let aps: APS
    }

    private func loadFixture() throws -> Envelope {
        let url = try #require(
            Bundle.module.url(forResource: "live_activity_start", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
    }

    @Test func decodesStartPayload() throws {
        let aps = try loadFixture().aps
        #expect(aps.event == "start")
        #expect(aps.attributesType == "CommuteActivityAttributes")
        #expect(aps.attributes == CommuteActivityAttributes(windowEnd: 1_792_364_400, firstHour: 7))
        #expect(aps.staleDate == aps.attributes.windowEnd)
        #expect(!aps.inputPushChannel.isEmpty)

        let state = aps.contentState
        #expect(state.highlight)
        #expect(state.places.map(\.name) == ["집", "회사"])
        #expect(state.maxPop == 70)
        #expect(state.places[0].rainWindow == nil)
        #expect(state.places[1].level == .high)
    }

    @Test func attributesTypeMatchesSwiftTypeName() throws {
        // ActivityKit은 attributes-type 값을 Swift 타입 이름과 비교한다.
        let aps = try loadFixture().aps
        #expect(aps.attributesType == String(describing: CommuteActivityAttributes.self))
    }

    @Test func roundTripsContentState() throws {
        let state = try loadFixture().aps.contentState
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(CommuteState.self, from: data) == state)
    }

    @Test func hourlyArraysCoverSameRange() throws {
        let state = try loadFixture().aps.contentState
        let counts = Set(state.places.map(\.pops.count))
        #expect(counts.count == 1)
        for place in state.places {
            #expect(place.pops.max() == place.maxPop)
        }
    }
}
