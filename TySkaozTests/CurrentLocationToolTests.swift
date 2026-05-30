import CoreLocation
import Foundation
import Testing
@testable import TySkaoz

@Suite @MainActor
struct CurrentLocationToolTests {

    private final class FakeProvider: LocationProviding, @unchecked Sendable {
        let result: Result<CLLocation, Error>
        init(_ result: Result<CLLocation, Error>) { self.result = result }
        func currentLocation() async throws -> CLLocation { try result.get() }
    }

    private func args(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test
    func returnsCoordinates() async throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945),
            altitude: 0,
            horizontalAccuracy: 12,
            verticalAccuracy: -1,
            timestamp: .now
        )
        let tool = CurrentLocationTool(provider: FakeProvider(.success(location)))
        let output = try await tool.execute(arguments: args(["include_address": false]))
        #expect(output.contains("48.85840"))
        #expect(output.contains("2.29450"))
        #expect(output.contains("±12 m"))
    }

    @Test
    func surfacesDeniedAsToolError() async {
        let tool = CurrentLocationTool(provider: FakeProvider(.failure(LocationError.denied)))
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(arguments: self.args([:]))
        }
    }
}
