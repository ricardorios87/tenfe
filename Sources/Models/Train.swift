import Foundation

struct Train: Identifiable, Codable, Sendable {
    let id: UUID
    let departureTime: Date
    let arrivalTime: Date
    let line: String
    let destination: String
    let tripId: String
    var delaySeconds: Int
    var isCancelled: Bool

    init(
        id: UUID = UUID(),
        departureTime: Date,
        arrivalTime: Date,
        line: String,
        destination: String,
        tripId: String = "",
        delaySeconds: Int = 0,
        isCancelled: Bool = false
    ) {
        self.id = id
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.line = line
        self.destination = destination
        self.tripId = tripId
        self.delaySeconds = delaySeconds
        self.isCancelled = isCancelled
    }

    var actualDepartureTime: Date {
        departureTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    var actualArrivalTime: Date {
        arrivalTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    var isDelayed: Bool {
        delaySeconds >= 60
    }

    var delayString: String? {
        guard delaySeconds >= 60 else { return nil }
        let minutes = delaySeconds / 60
        return "+\(minutes) min"
    }

    var departureTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: actualDepartureTime)
    }

    var scheduledDepartureTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: departureTime)
    }

    var timeUntilDeparture: String {
        if isCancelled {
            return "Cancelled"
        }

        let interval = actualDepartureTime.timeIntervalSince(Date())
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