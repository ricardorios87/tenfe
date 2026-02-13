import Foundation

// Renfe API Service using GTFS static data + GTFS-RT real-time updates
actor RenfeAPI {
    nonisolated static let shared = RenfeAPI()

    // GTFS data sources
    private static let gtfsZipURL = "https://ssl.renfe.com/ftransit/Fichero_CER_FOMENTO/fomento_transit.zip"
    private static let gtfsRealtimeURL = "https://gtfsrt.renfe.com/trip_updates.json"

    // Fallback HTML scraping
    private static let htmlScheduleURL = "https://horarios.renfe.com/cer/hjcer310.jsp"
    private let madridNucleoId = "10"

    // GTFS data cache
    private var tripInfoCache: [String: GTFSTripInfo] = [:]
    private var stopTimesCache: [String: [GTFSStopTimeEntry]] = [:]
    private var cacheDate: String?

    // MARK: - Internal Types

    private struct GTFSTripInfo: Sendable {
        let tripId: String
        let routeId: String
        let line: String
    }

    private struct GTFSStopTimeEntry: Sendable {
        let tripId: String
        let arrivalTime: String   // HH:mm:ss
        let departureTime: String // HH:mm:ss
        let stopId: String
        let stopSequence: Int
    }

    // MARK: - GTFS-RT JSON Models

    private struct GTFSRTFeed: Codable, Sendable {
        let header: GTFSRTHeader
        let entity: [GTFSRTEntity]
    }

    private struct GTFSRTHeader: Codable, Sendable {
        let gtfsRealtimeVersion: String?
        let timestamp: String?
    }

    private struct GTFSRTEntity: Codable, Sendable {
        let id: String
        let tripUpdate: GTFSRTTripUpdate
    }

    private struct GTFSRTTripUpdate: Codable, Sendable {
        let trip: GTFSRTTrip
        let stopTimeUpdate: [GTFSRTStopTimeUpdate]?
        let delay: Int?
    }

    private struct GTFSRTTrip: Codable, Sendable {
        let tripId: String
        let scheduleRelationship: String?
    }

    private struct GTFSRTStopTimeUpdate: Codable, Sendable {
        let stopId: String?
        let arrival: GTFSRTStopTimeEvent?
        let scheduleRelationship: String?
    }

    private struct GTFSRTStopTimeEvent: Codable, Sendable {
        let delay: Int?
        let time: String?
    }

    // MARK: - Public API

    func fetchTrainsBetweenStations(
        from originName: String,
        to destinationName: String
    ) async throws -> [Train] {
        guard let originCode = RenfeAPI.getRenfeStationCode(for: originName) else {
            throw APIError.stationNotFound
        }
        guard let destCode = RenfeAPI.getRenfeStationCode(for: destinationName) else {
            throw APIError.stationNotFound
        }

        // Try GTFS approach first
        do {
            try await loadGTFSDataIfNeeded()
            var trains = buildSchedule(
                originCode: originCode,
                destCode: destCode,
                destinationName: destinationName
            )

            if !trains.isEmpty {
                trains = await applyRealtimeDelays(
                    to: trains,
                    originCode: originCode,
                    destCode: destCode
                )
                return trains
            }
        } catch {
            print("[Tenfe] GTFS approach failed: \(error.localizedDescription), falling back to HTML")
        }

        // Fallback to HTML scraping
        return try await fetchScheduleFromHTML(
            nucleo: madridNucleoId,
            origin: originCode,
            destination: destCode,
            destinationName: destinationName
        )
    }

    // MARK: - GTFS Data Loading

    private func loadGTFSDataIfNeeded() async throws {
        let today = Self.todayString()
        if cacheDate == today && !tripInfoCache.isEmpty {
            return
        }

        let cacheDir = Self.gtfsCacheDirectory()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let zipPath = cacheDir.appendingPathComponent("gtfs.zip")
        let dateMarkerPath = cacheDir.appendingPathComponent("gtfs_date.txt")

        // Check if we already have today's zip
        let needsDownload: Bool
        if FileManager.default.fileExists(atPath: zipPath.path),
           let markerData = try? String(contentsOf: dateMarkerPath, encoding: .utf8),
           markerData.trimmingCharacters(in: .whitespacesAndNewlines) == today {
            needsDownload = false
        } else {
            needsDownload = true
        }

        if needsDownload {
            try await downloadGTFSZip(to: zipPath)
            try today.write(to: dateMarkerPath, atomically: true, encoding: .utf8)
        }

        try await extractAndParseGTFS(zipPath: zipPath, cacheDir: cacheDir, today: today)
    }

    private func downloadGTFSZip(to path: URL) async throws {
        guard let url = URL(string: Self.gtfsZipURL) else {
            throw APIError.invalidURL
        }

        // Use a session that tolerates potential SSL issues with ssl.renfe.com
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: SSLTolerantDelegate.shared, delegateQueue: nil)

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serviceUnavailable
        }

        try data.write(to: path)
        print("[Tenfe] Downloaded GTFS data: \(data.count / 1024)KB")
    }

    private func extractAndParseGTFS(zipPath: URL, cacheDir: URL, today: String) async throws {
        // Step 1: Extract small files using unzip
        try await runShell(
            "unzip -o '\(zipPath.path)' calendar.txt trips.txt routes.txt -d '\(cacheDir.path)' 2>/dev/null"
        )

        // Step 2: Parse calendar → find today's Madrid service_id
        let serviceId = try parseTodayServiceId(
            from: cacheDir.appendingPathComponent("calendar.txt"),
            today: today
        )
        print("[Tenfe] Today's Madrid service_id: \(serviceId)")

        // Step 3: Parse routes → line names
        let routes = try parseRoutes(
            from: cacheDir.appendingPathComponent("routes.txt")
        )

        // Step 4: Parse trips → trip info for today's service
        tripInfoCache = try parseTrips(
            from: cacheDir.appendingPathComponent("trips.txt"),
            serviceId: serviceId,
            routes: routes
        )
        print("[Tenfe] Loaded \(tripInfoCache.count) trips for today")

        // Step 5: Filter and parse stop_times (pipe through grep, never writes 273MB to disk)
        let filteredPath = cacheDir.appendingPathComponent("filtered_stop_times.txt")
        // Use grep to efficiently filter: only keep lines starting with the service_id prefix
        try await runShell(
            "unzip -p '\(zipPath.path)' stop_times.txt | grep '^\\(\(serviceId)\\)' > '\(filteredPath.path)'"
        )

        stopTimesCache = try parseStopTimes(from: filteredPath)
        print("[Tenfe] Loaded stop times for \(stopTimesCache.count) trips")

        cacheDate = today
    }

    // MARK: - GTFS Parsing

    private func parseTodayServiceId(from path: URL, today: String) throws -> String {
        let content = try String(contentsOf: path, encoding: .utf8)
        let todayDate = today // YYYYMMDD

        // Calendar format: service_id,mon,tue,wed,thu,fri,sat,sun,start_date,end_date
        // Find the service_id for Madrid (starts with "10") active today
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: Date())
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        // CSV columns: mon=1, tue=2, wed=3, thu=4, fri=5, sat=6, sun=7
        let csvDayColumn: Int
        switch dayOfWeek {
        case 1: csvDayColumn = 7 // Sunday
        case 2: csvDayColumn = 1 // Monday
        case 3: csvDayColumn = 2 // Tuesday
        case 4: csvDayColumn = 3 // Wednesday
        case 5: csvDayColumn = 4 // Thursday
        case 6: csvDayColumn = 5 // Friday
        case 7: csvDayColumn = 6 // Saturday
        default: csvDayColumn = 1
        }

        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 10 else { continue }

            let serviceId = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard serviceId.hasPrefix("10") else { continue }

            // Check if this service is active on today's day of week
            let dayActive = String(parts[csvDayColumn]).trimmingCharacters(in: .whitespaces)
            guard dayActive == "1" else { continue }

            // Check date range
            let startDate = String(parts[8]).trimmingCharacters(in: .whitespaces)
            let endDate = String(parts[9]).trimmingCharacters(in: .whitespaces)
            if startDate <= todayDate && endDate >= todayDate {
                return serviceId
            }
        }

        throw APIError.parseError
    }

    private func parseRoutes(from path: URL) throws -> [String: String] {
        let content = try String(contentsOf: path, encoding: .utf8)
        var routes: [String: String] = [:] // route_id → line name (e.g., "C1", "C2")

        // Format: route_id,route_short_name,route_long_name,route_type,...
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }

            let routeId = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard routeId.hasPrefix("10") else { continue } // Madrid only

            let lineName = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if !lineName.isEmpty {
                routes[routeId] = lineName
            }
        }

        return routes
    }

    private func parseTrips(
        from path: URL,
        serviceId: String,
        routes: [String: String]
    ) throws -> [String: GTFSTripInfo] {
        let content = try String(contentsOf: path, encoding: .utf8)
        var trips: [String: GTFSTripInfo] = [:]

        // Format: route_id,service_id,trip_id,trip_headsign,...
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }

            let routeId = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let tripServiceId = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let tripId = String(parts[2]).trimmingCharacters(in: .whitespaces)

            guard tripServiceId == serviceId else { continue }

            let lineName = routes[routeId] ?? "C"
            trips[tripId] = GTFSTripInfo(
                tripId: tripId,
                routeId: routeId,
                line: lineName
            )
        }

        return trips
    }

    private func parseStopTimes(from path: URL) throws -> [String: [GTFSStopTimeEntry]] {
        let content = try String(contentsOf: path, encoding: .utf8)
        var result: [String: [GTFSStopTimeEntry]] = [:]

        // Format: trip_id,arrival_time,departure_time,stop_id,stop_sequence
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 5 else { continue }

            let tripId = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let arrivalTime = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let departureTime = String(parts[2]).trimmingCharacters(in: .whitespaces)
            let stopId = String(parts[3]).trimmingCharacters(in: .whitespaces)
            let stopSequence = Int(parts[4].trimmingCharacters(in: .whitespaces)) ?? 0

            let entry = GTFSStopTimeEntry(
                tripId: tripId,
                arrivalTime: arrivalTime,
                departureTime: departureTime,
                stopId: stopId,
                stopSequence: stopSequence
            )

            result[tripId, default: []].append(entry)
        }

        return result
    }

    // MARK: - Schedule Building

    private func buildSchedule(
        originCode: String,
        destCode: String,
        destinationName: String
    ) -> [Train] {
        let now = Date()
        let calendar = Calendar.current
        var trains: [Train] = []

        for (tripId, stopTimes) in stopTimesCache {
            // Find origin and destination stop entries for this trip
            let originStop = stopTimes.first { $0.stopId == originCode }
            let destStop = stopTimes.first { $0.stopId == destCode }

            guard let origin = originStop, let dest = destStop else { continue }

            // Origin must come before destination in the trip sequence
            guard origin.stopSequence < dest.stopSequence else { continue }

            // Parse times
            guard let departureDate = Self.parseGTFSTime(origin.departureTime, relativeTo: now),
                  let arrivalDate = Self.parseGTFSTime(dest.arrivalTime, relativeTo: now) else {
                continue
            }

            // Only include future trains
            guard departureDate > now else { continue }

            // Get line info
            let line = tripInfoCache[tripId]?.line ?? "C"

            let train = Train(
                departureTime: departureDate,
                arrivalTime: arrivalDate,
                line: line,
                destination: destinationName,
                tripId: tripId
            )
            trains.append(train)
        }

        return Array(trains.sorted { $0.departureTime < $1.departureTime }.prefix(20))
    }

    // MARK: - GTFS Realtime

    private func applyRealtimeDelays(
        to trains: [Train],
        originCode: String,
        destCode: String
    ) async -> [Train] {
        guard let updates = try? await fetchRealtimeUpdates() else {
            return trains
        }

        return trains.map { train in
            guard !train.tripId.isEmpty,
                  let update = updates[train.tripId] else {
                return train
            }

            var modified = train
            modified.delaySeconds = update.delay

            // Check if origin or destination stops are skipped (cancelled)
            if update.skippedStops.contains(originCode) || update.skippedStops.contains(destCode) {
                modified.isCancelled = true
            }

            return modified
        }
    }

    private func fetchRealtimeUpdates() async throws -> [String: (delay: Int, skippedStops: Set<String>)] {
        guard let url = URL(string: Self.gtfsRealtimeURL) else {
            throw APIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let feed = try JSONDecoder().decode(GTFSRTFeed.self, from: data)

        var updates: [String: (delay: Int, skippedStops: Set<String>)] = [:]
        for entity in feed.entity {
            let tripId = entity.tripUpdate.trip.tripId
            let delay = entity.tripUpdate.delay ?? 0
            let skippedStops = Set(
                entity.tripUpdate.stopTimeUpdate?
                    .filter { $0.scheduleRelationship == "SKIPPED" }
                    .compactMap { $0.stopId } ?? []
            )
            updates[tripId] = (delay: delay, skippedStops: skippedStops)
        }

        return updates
    }

    // MARK: - HTML Fallback (original scraping approach)

    private func fetchScheduleFromHTML(
        nucleo: String,
        origin: String,
        destination: String,
        destinationName: String
    ) async throws -> [Train] {
        guard let url = URL(string: Self.htmlScheduleURL) else {
            throw APIError.invalidURL
        }

        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let todayDate = dateFormatter.string(from: now)

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)

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

        let trains = parseScheduleHTML(html, destinationName: destinationName)

        guard !trains.isEmpty else {
            throw APIError.parseError
        }

        return trains
    }

    private func parseScheduleHTML(_ html: String, destinationName: String) -> [Train] {
        var trains: [Train] = []
        let calendar = Calendar.current
        let now = Date()

        let rowPattern = #"<tr[^>]*>.*?</tr>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return trains
        }

        let htmlRange = NSRange(html.startIndex..., in: html)
        let rowMatches = rowRegex.matches(in: html, options: [], range: htmlRange)

        for rowMatch in rowMatches {
            guard let rowRange = Range(rowMatch.range, in: html) else { continue }
            let rowHTML = String(html[rowRange])

            if rowHTML.contains("<th") || rowHTML.contains("cabe") { continue }

            let lineClassPattern = #"_10C(\d+[a-z]?)"#
            var line = "C"
            if let lineRegex = try? NSRegularExpression(pattern: lineClassPattern, options: .caseInsensitive) {
                let lineRange = NSRange(rowHTML.startIndex..., in: rowHTML)
                if let lineMatch = lineRegex.firstMatch(in: rowHTML, options: [], range: lineRange),
                   let matchRange = Range(lineMatch.range(at: 1), in: rowHTML) {
                    line = "C\(rowHTML[matchRange])".uppercased()
                }
            }

            let timePattern = #">(\d{1,2})\.(\d{2})<"#
            guard let timeRegex = try? NSRegularExpression(pattern: timePattern, options: []) else { continue }

            let rowNSRange = NSRange(rowHTML.startIndex..., in: rowHTML)
            let timeMatches = timeRegex.matches(in: rowHTML, options: [], range: rowNSRange)

            if timeMatches.count >= 2 {
                if let depHourRange = Range(timeMatches[0].range(at: 1), in: rowHTML),
                   let depMinRange = Range(timeMatches[0].range(at: 2), in: rowHTML),
                   let arrHourRange = Range(timeMatches[1].range(at: 1), in: rowHTML),
                   let arrMinRange = Range(timeMatches[1].range(at: 2), in: rowHTML) {

                    let depHour = Int(rowHTML[depHourRange]) ?? 0
                    let depMin = Int(rowHTML[depMinRange]) ?? 0
                    let arrHour = Int(rowHTML[arrHourRange]) ?? 0
                    let arrMin = Int(rowHTML[arrMinRange]) ?? 0

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

                        if arrivalDate < departureDate {
                            arrivalDate = calendar.date(byAdding: .day, value: 1, to: arrivalDate) ?? arrivalDate
                        }

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

        return Array(trains.sorted { $0.departureTime < $1.departureTime }.prefix(20))
    }

    // MARK: - Helpers

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private static func gtfsCacheDirectory() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("com.tenfe.gtfs", isDirectory: true)
    }

    /// Parse GTFS time string (HH:mm:ss, can exceed 24:00 for overnight trips) to a Date
    private static func parseGTFSTime(_ timeStr: String, relativeTo date: Date) -> Date? {
        let parts = timeStr.split(separator: ":")
        guard parts.count >= 2,
              var hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)

        // GTFS times can exceed 24:00 for trips crossing midnight
        let extraDays = hour / 24
        hour = hour % 24

        components.hour = hour
        components.minute = minute
        components.second = 0

        guard var result = calendar.date(from: components) else { return nil }

        if extraDays > 0 {
            result = calendar.date(byAdding: .day, value: extraDays, to: result) ?? result
        }

        return result
    }

    /// Run a shell command asynchronously (non-blocking for the actor)
    @discardableResult
    private func runShell(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { _ in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                // Don't check termination status - grep returns 1 for no matches which is OK
                continuation.resume(returning: output)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
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

// MARK: - SSL Delegate for Renfe's potentially problematic SSL cert

private final class SSLTolerantDelegate: NSObject, URLSessionDelegate, Sendable {
    static let shared = SSLTolerantDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Madrid Cercanías Station Codes (Renfe format)

extension RenfeAPI {
    // These are also the GTFS stop_ids (same codes used in both systems)
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

    nonisolated static func getRenfeStationCode(for name: String) -> String? {
        let normalizedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return renfeStationCodes.first { key, _ in
            key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedName
        }?.value
    }

    nonisolated static func getStationCode(for name: String) -> Int? {
        guard let code = getRenfeStationCode(for: name) else { return nil }
        return Int(code)
    }
}
