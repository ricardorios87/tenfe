#!/usr/bin/env swift

import Foundation

// Simple test to verify Renfe API connectivity
let url = URL(string: "https://data.renfe.com/api/3/action/datastore_search?resource_id=a2368cff-1562-4dde-8466-9635ea3a572a&limit=5&q=recoletos")!

let task = URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
        print("❌ Error: \(error)")
        exit(1)
    }

    guard let data = data else {
        print("❌ No data received")
        exit(1)
    }

    do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool,
           success == true,
           let result = json["result"] as? [String: Any],
           let records = result["records"] as? [[String: Any]] {

            print("✅ API Connection successful!")
            print("\n📍 Found stations matching 'recoletos':")

            for record in records {
                if let name = record["DESCRIPCION"] as? String,
                   let code = record["CÓDIGO"] {
                    print("  - \(name) (Code: \(code))")
                }
            }
        } else {
            print("❌ Unexpected response format")
        }
    } catch {
        print("❌ JSON parsing error: \(error)")
    }
    exit(0)
}

task.resume()
RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))