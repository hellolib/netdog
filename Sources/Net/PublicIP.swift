import Foundation

struct PublicAddress {
    var v4: String?
    var v6: String?
    var country: String?
}

/// Same endpoint Stats uses. Fetched once at launch by default; no periodic
/// refresh (the right-click menu exposes a manual refresh).
enum PublicIP {
    static func fetch(completion: @escaping (PublicAddress?) -> Void) {
        guard let url = URL(string: "https://ip.mac-stats.com") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, _, error in
            struct Response: Decodable {
                let ipv4: String?
                let ipv6: String?
                let country: String?
            }

            guard let data, error == nil,
                  let model = try? JSONDecoder().decode(Response.self, from: data) else {
                completion(nil)
                return
            }

            var address = PublicAddress()
            if let ip = model.ipv4, isIPv4(ip) {
                address.v4 = ip
            }
            if let ip = model.ipv6, !ip.isEmpty, !isIPv4(ip) {
                address.v6 = ip
            }
            address.country = model.country

            if address.v4 == nil && address.v6 == nil {
                completion(nil)
            } else {
                completion(address)
            }
        }.resume()
    }

    private static func isIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), part.count > 0, part.count <= 3 else { return false }
            return value >= 0 && value < 256
        }
    }
}
