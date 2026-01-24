import Foundation

struct Train: Identifiable, Codable, Sendable {
    let id: UUID
    let departureTime: Date
    let arrivalTime: Date
    let line: String
    let destination: String

    init(id: UUID = UUID(), departureTime: Date, arrivalTime: Date, line: String, destination: String) {
        self.id = id
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.line = line
        self.destination = destination
    }

    var departureTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: departureTime)
    }

    var timeUntilDeparture: String {
        let interval = departureTime.timeIntervalSince(Date())
        if interval < 0 {
            return "Departed"
        }

        let minutes = Int(interval / 60)
        if minutes < 1 {
            return "Now"
        } else if minutes == 1 {
            return "in 1 min"
        } else {
            return "in \(minutes) min"
        }
    }
}

struct Route: Codable, Sendable {
    var origin: String
    var destination: String

    init(origin: String = "Recoletos", destination: String = "Vicálvaro") {
        self.origin = origin
        self.destination = destination
    }
}