import Foundation

struct Trip: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var route: Route
    var leaveTime: Date
    var walkTimeMinutes: Int
    var enable15MinWarning: Bool
    var enableTimeToLeaveAlert: Bool

    var displayName: String {
        if !name.isEmpty { return name }
        return "\(route.origin) → \(route.destination)"
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        route: Route = Route(),
        leaveTime: Date = Calendar.current.date(from: DateComponents(hour: 18, minute: 30)) ?? Date(),
        walkTimeMinutes: Int = 5,
        enable15MinWarning: Bool = true,
        enableTimeToLeaveAlert: Bool = true
    ) {
        self.id = id
        self.name = name
        self.route = route
        self.leaveTime = leaveTime
        self.walkTimeMinutes = walkTimeMinutes
        self.enable15MinWarning = enable15MinWarning
        self.enableTimeToLeaveAlert = enableTimeToLeaveAlert
    }
}

struct AppSettings: Codable, Sendable {
    var trips: [Trip]
    var activeTripId: UUID?

    var activeTrip: Trip? {
        if let id = activeTripId, let trip = trips.first(where: { $0.id == id }) {
            return trip
        }
        return trips.first
    }

    // Backward-compat computed accessors — delegate to activeTrip
    var route: Route {
        get { activeTrip?.route ?? Route() }
        set {
            guard let idx = activeTripIndex else { return }
            trips[idx].route = newValue
        }
    }

    var leaveTime: Date {
        get { activeTrip?.leaveTime ?? Calendar.current.date(from: DateComponents(hour: 18, minute: 30)) ?? Date() }
        set {
            guard let idx = activeTripIndex else { return }
            trips[idx].leaveTime = newValue
        }
    }

    var walkTimeMinutes: Int {
        get { activeTrip?.walkTimeMinutes ?? 5 }
        set {
            guard let idx = activeTripIndex else { return }
            trips[idx].walkTimeMinutes = newValue
        }
    }

    var enable15MinWarning: Bool {
        get { activeTrip?.enable15MinWarning ?? true }
        set {
            guard let idx = activeTripIndex else { return }
            trips[idx].enable15MinWarning = newValue
        }
    }

    var enableTimeToLeaveAlert: Bool {
        get { activeTrip?.enableTimeToLeaveAlert ?? true }
        set {
            guard let idx = activeTripIndex else { return }
            trips[idx].enableTimeToLeaveAlert = newValue
        }
    }

    var formattedLeaveTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: leaveTime)
    }

    private var activeTripIndex: Int? {
        if let id = activeTripId {
            return trips.firstIndex(where: { $0.id == id })
        }
        return trips.indices.first
    }

    init() {
        let trip = Trip()
        self.trips = [trip]
        self.activeTripId = trip.id
    }

    // Custom Codable for migration from legacy single-route format
    enum CodingKeys: String, CodingKey {
        case trips, activeTripId
        // Legacy keys
        case route, leaveTime, walkTimeMinutes, enable15MinWarning, enableTimeToLeaveAlert
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try new format first
        if let trips = try? container.decode([Trip].self, forKey: .trips) {
            self.trips = trips
            self.activeTripId = try? container.decode(UUID.self, forKey: .activeTripId)
        } else {
            // Legacy format: read individual fields and build a single Trip
            let route = (try? container.decode(Route.self, forKey: .route)) ?? Route()
            let leaveTime = (try? container.decode(Date.self, forKey: .leaveTime))
                ?? Calendar.current.date(from: DateComponents(hour: 18, minute: 30)) ?? Date()
            let walkTimeMinutes = (try? container.decode(Int.self, forKey: .walkTimeMinutes)) ?? 5
            let enable15MinWarning = (try? container.decode(Bool.self, forKey: .enable15MinWarning)) ?? true
            let enableTimeToLeaveAlert = (try? container.decode(Bool.self, forKey: .enableTimeToLeaveAlert)) ?? true

            let trip = Trip(
                route: route,
                leaveTime: leaveTime,
                walkTimeMinutes: walkTimeMinutes,
                enable15MinWarning: enable15MinWarning,
                enableTimeToLeaveAlert: enableTimeToLeaveAlert
            )
            self.trips = [trip]
            self.activeTripId = trip.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trips, forKey: .trips)
        try container.encodeIfPresent(activeTripId, forKey: .activeTripId)
    }
}

// List of Madrid Cercanías stations (subset for MVP)
struct Station {
    static let madridStations = [
        "Atocha",
        "Chamartín",
        "Nuevos Ministerios",
        "Recoletos",
        "Sol",
        "Vicálvaro",
        "Coslada",
        "Torrejón de Ardoz",
        "Alcalá de Henares",
        "Príncipe Pío",
        "Pirámides",
        "Delicias",
        "Méndez Álvaro",
        "Aluche",
        "Laguna",
        "Embajadores"
    ].sorted()
}
