import Foundation

// Renfe API Service for fetching real train data
actor RenfeAPI {
    nonisolated static let shared = RenfeAPI()

    // Renfe Cercanías schedule endpoint
    private let scheduleURL = "https://horarios.renfe.com/cer/hjcer310.jsp"
    private let madridNucleoId = "10" // Madrid Cercanías núcleo

    // MARK: - Train Schedule Methods

    func fetchTrainsBetweenStations(
        from originName: String,
        to destinationName: String
    ) async throws -> [Train] {
        // Get Renfe station codes
        guard let originCode = RenfeAPI.getRenfeStationCode(for: originName) else {
            throw APIError.stationNotFound
        }

        guard let destinationCode = RenfeAPI.getRenfeStationCode(for: destinationName) else {
            throw APIError.stationNotFound
        }

        // Fetch real schedule from Renfe
        return try await fetchRealSchedule(
            nucleo: madridNucleoId,
            origin: originCode,
            destination: destinationCode,
            destinationName: destinationName
        )
    }

    private func fetchRealSchedule(
        nucleo: String,
        origin: String,
        destination: String,
        destinationName: String
    ) async throws -> [Train] {
        guard let url = URL(string: scheduleURL) else {
            throw APIError.invalidURL
        }

        // Format date and time
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let todayDate = dateFormatter.string(from: now)

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)

        // Build form data
        let formData: [String: String] = [
            "TXTInfo": "",
            "cp": "NO",
            "d": destination,
            "df": todayDate,
            "hd": "26",
            "ho": String(hour),
            "i": "s",
            "nucleo": nucleo,
            "o": origin
        ]

        // Create URL-encoded body
        let bodyString = formData.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.httpBody = bodyString.data(using: .utf8)
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw APIError.noData
        }

        // Parse the HTML response
        let trains = parseScheduleHTML(html, destinationName: destinationName)

        guard !trains.isEmpty else {
            throw APIError.parseError
        }

        return trains
    }

    // MARK: - HTML Parsing

    private func parseScheduleHTML(_ html: String, destinationName: String) -> [Train] {
        var trains: [Train] = []
        let calendar = Calendar.current
        let now = Date()

        // Find all table rows that contain schedule data
        let rowPattern = #"<tr[^>]*>.*?</tr>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return trains
        }

        let htmlRange = NSRange(html.startIndex..., in: html)
        let rowMatches = rowRegex.matches(in: html, options: [], range: htmlRange)

        for rowMatch in rowMatches {
            guard let rowRange = Range(rowMatch.range, in: html) else { continue }
            let rowHTML = String(html[rowRange])

            // Skip header rows and rows without schedule data
            if rowHTML.contains("<th") || rowHTML.contains("cabe") { continue }

            // Look for line class pattern like "_10C2" or "_10C7"
            let lineClassPattern = #"_10C(\d+[a-z]?)"#
            var line = "C"
            if let lineRegex = try? NSRegularExpression(pattern: lineClassPattern, options: .caseInsensitive) {
                let lineRange = NSRange(rowHTML.startIndex..., in: rowHTML)
                if let lineMatch = lineRegex.firstMatch(in: rowHTML, options: [], range: lineRange),
                   let matchRange = Range(lineMatch.range(at: 1), in: rowHTML) {
                    line = "C-\(rowHTML[matchRange])".uppercased()
                }
            }

            // Extract times from td elements - looking for pattern like ">17.00<"
            let timePattern = #">(\d{1,2})\.(\d{2})<"#
            guard let timeRegex = try? NSRegularExpression(pattern: timePattern, options: []) else { continue }

            let rowNSRange = NSRange(rowHTML.startIndex..., in: rowHTML)
            let timeMatches = timeRegex.matches(in: rowHTML, options: [], range: rowNSRange)

            // We need at least 2 times (departure and arrival)
            if timeMatches.count >= 2 {
                // First match is departure, second is arrival
                if let depHourRange = Range(timeMatches[0].range(at: 1), in: rowHTML),
                   let depMinRange = Range(timeMatches[0].range(at: 2), in: rowHTML),
                   let arrHourRange = Range(timeMatches[1].range(at: 1), in: rowHTML),
                   let arrMinRange = Range(timeMatches[1].range(at: 2), in: rowHTML) {

                    let depHour = Int(rowHTML[depHourRange]) ?? 0
                    let depMin = Int(rowHTML[depMinRange]) ?? 0
                    let arrHour = Int(rowHTML[arrHourRange]) ?? 0
                    let arrMin = Int(rowHTML[arrMinRange]) ?? 0

                    // Create departure and arrival dates
                    var depComponents = calendar.dateComponents([.year, .month, .day], from: now)
                    depComponents.hour = depHour
                    depComponents.minute = depMin
                    depComponents.second = 0

                    var arrComponents = calendar.dateComponents([.year, .month, .day], from: now)
                    arrComponents.hour = arrHour
                    arrComponents.minute = arrMin
                    arrComponents.second = 0

                    if let departureDate = calendar.date(from: depComponents),
                       var arrivalDate = calendar.date(from: arrComponents) {

                        // Handle arrival after midnight
                        if arrivalDate < departureDate {
                            arrivalDate = calendar.date(byAdding: .day, value: 1, to: arrivalDate) ?? arrivalDate
                        }

                        // Only include future trains
                        if departureDate > now {
                            let train = Train(
                                departureTime: departureDate,
                                arrivalTime: arrivalDate,
                                line: line,
                                destination: destinationName
                            )
                            trains.append(train)
                        }
                    }
                }
            }
        }

        // Sort by departure time and limit to reasonable number
        return Array(trains.sorted { $0.departureTime < $1.departureTime }.prefix(20))
    }

    // MARK: - Error Types

    enum APIError: LocalizedError, Sendable {
        case invalidURL
        case noData
        case stationNotFound
        case parseError
        case serviceUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noData:
                return "No data received from Renfe"
            case .stationNotFound:
                return "Station not found"
            case .parseError:
                return "Could not parse schedule data"
            case .serviceUnavailable:
                return "Renfe service unavailable"
            }
        }
    }
}

// MARK: - Madrid Cercanías Station Codes (Renfe format)

extension RenfeAPI {
    // Renfe Cercanías station codes for Madrid núcleo
    // These are the official codes used by horarios.renfe.com
    nonisolated static let renfeStationCodes: [String: String] = [
        "Atocha": "18000",
        "Chamartín": "17000",
        "Nuevos Ministerios": "18002",
        "Recoletos": "18001",
        "Sol": "18101",
        "Vicálvaro": "70100",
        "Coslada": "70108",
        "Torrejón de Ardoz": "70102",
        "Alcalá de Henares": "70103",
        "Príncipe Pío": "10000",
        "Pirámides": "18005",
        "Delicias": "18004",
        "Méndez Álvaro": "18003",
        "Aluche": "35600",
        "Laguna": "35608",
        "Embajadores": "35609"
    ]

    // Lookup station code with case and diacritic-insensitive matching
    nonisolated static func getRenfeStationCode(for name: String) -> String? {
        let normalizedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return renfeStationCodes.first { key, _ in
            key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedName
        }?.value
    }

    // Keep old method for compatibility
    nonisolated static func getStationCode(for name: String) -> Int? {
        guard let code = getRenfeStationCode(for: name) else { return nil }
        return Int(code)
    }
}
