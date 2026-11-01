import Foundation

public enum RouteTransport: Sendable, Equatable, Hashable, CaseIterable {
    case automobile
    case walking
    case transit
}

public protocol RoutePathProviding: Sendable {
    func path(from: GeoCoordinate, to: GeoCoordinate, transport: RouteTransport) async throws -> [GeoCoordinate]
}

/// Plans a route by trying the supported transport modes in product order.
public struct FallbackRoutePlanner: RoutePlanning, Sendable {
    private let provider: any RoutePathProviding

    public init(provider: any RoutePathProviding) {
        self.provider = provider
    }

    /// Walking only: repair tries each edge once instead of walking the whole fallback chain.
    public func planWalking(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        try Task.checkCancellation()
        let points = try await provider.path(from: from, to: to, transport: .walking)
        try Task.checkCancellation()
        _ = try PlannedRoute(points: points)
        return points
    }

    public func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        for transport in RouteTransport.allCases {
            try Task.checkCancellation()
            do {
                let points = try await provider.path(from: from, to: to, transport: transport)
                try Task.checkCancellation()

                // Validation keeps provider failures from stopping the ordered fallback. The
                // planner intentionally returns the provider geometry so callers can preserve
                // every road vertex; PlannedRoute performs any adjacent-point normalization.
                _ = try PlannedRoute(points: points)
                try Task.checkCancellation()
                return points
            } catch is CancellationError {
                throw CancellationError()
            } catch let throttled as RoutePlanningThrottled {
                // Another transport would only be refused too; let the caller wait.
                throw throttled
            } catch {
                try Task.checkCancellation()
            }
        }
        throw RouteExecutionFailure.planningFailed
    }
}
