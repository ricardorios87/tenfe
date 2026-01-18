import Foundation
import Combine

class TrainService: ObservableObject {
    @Published var nextTrains: [Train] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private let renfeAPI = RenfeAPI.shared
    private var currentRoute: (origin: String, destination: String)?

    init() {
        // Will be initialized with route from settings
    }

    func refreshTrains() {
        guard let route = currentRoute else {
            // Use default route if not set
            refreshTrains(from: "Recoletos", to: "Vicálvaro")
            return
        }
        refreshTrains(from: route.origin, to: route.destination)
    }

    func refreshTrains(from origin: String, to destination: String) {
        isLoading = true
        errorMessage = nil
        currentRoute = (origin, destination)

        renfeAPI.fetchTrainsBetweenStations(from: origin, to: destination) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let trains):
                    self?.nextTrains = trains
                    self?.errorMessage = nil
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                    self?.nextTrains = []
                }
            }
        }
    }

    func getTrainsForRoute(from origin: String, to destination: String) -> [Train] {
        // Update current route and refresh
        currentRoute = (origin, destination)
        refreshTrains(from: origin, to: destination)
        return nextTrains
    }

    func getNextTrainAfter(date: Date) -> Train? {
        return nextTrains.first { train in
            train.departureTime > date
        }
    }

    func setRoute(_ route: Route) {
        currentRoute = (route.origin, route.destination)
        refreshTrains()
    }
}

