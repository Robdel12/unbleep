import Foundation

@MainActor
final class CatalogResponseCache {
    private struct Entry {
        let data: Data
        let expires: ContinuousClock.Instant
    }

    private var responses: [URL: Entry] = [:]
    private var pending: [URL: Task<Data, Error>] = [:]

    func value<T>(
        for url: URL, decode: (Data) throws -> T, fetch: @escaping @MainActor () async throws -> Data
    ) async throws -> T {
        if let entry = responses[url], entry.expires > .now {
            return try decode(entry.data)
        }
        if let request = pending[url] {
            return try decode(await request.value)
        }

        let request = Task { try await fetch() }
        pending[url] = request
        defer { pending[url] = nil }
        let data = try await request.value
        let value = try decode(data)
        if responses.count >= 128, let oldest = responses.min(by: { $0.value.expires < $1.value.expires }) {
            responses.removeValue(forKey: oldest.key)
        }
        responses[url] = Entry(data: data, expires: .now.advanced(by: .seconds(900)))
        return value
    }
}
