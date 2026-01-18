import Foundation

struct AppSettings: Codable {
    var route: Route
    var leaveTime: Date
    var walkTimeMinutes: Int
    var enable15MinWarning: Bool
    var enableTimeToLeaveAlert: Bool

    init() {
        self.route = Route()
        self.leaveTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 30)) ?? Date()
        self.walkTimeMinutes = 5
        self.enable15MinWarning = true
        self.enableTimeToLeaveAlert = true
    }

    var formattedLeaveTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: leaveTime)
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