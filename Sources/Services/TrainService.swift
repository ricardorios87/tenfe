import Foundation
import Observation

@Observable
@MainActor
final class TrainService {
    var nextTrains: [Train] = []
    var isLoading = false
    var errorMessage: String?

    private let renfeAPI = RenfeAPI.shared
    private var currentRoute: Route?

    init() {
        // Will be initialized with route from settings
    }

    func refreshTrains() async {
        guard let route = currentRoute else {
            // Use default route if not set
            await refreshTrains(from: "Recoletos", to: "Vicálvaro")
            return
        }
        await refreshTrains(from: route.origin, to: route.destination)
    }

    func refreshTrains(from origin: String, to destination: String) async {
        currentRoute = Route(origin: origin, destination: destination)
        isLoading = true
        errorMessage = nil

        do {
            let trains = try await renfeAPI.fetchTrainsBetweenStations(from: origin, to: destination)
            self.nextTrains = trains
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            self.nextTrains = []
        }

        self.isLoading = false
    }

    func getTrainsForRoute(from origin: String, to destination: String) async -> [Train] {
        // Update current route and refresh
        await refreshTrains(from: origin, to: destination)
        return nextTrains
    }

    func getNextTrainAfter(date: Date) -> Train? {
        return nextTrains.first { train in
            train.departureTime > date
        }
    }

    func setRoute(_ route: Route) async {
        currentRoute = route
        await refreshTrains()
    }
}

