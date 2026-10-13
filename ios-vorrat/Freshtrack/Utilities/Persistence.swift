import Foundation

/// Tiny JSON-file persistence in the app's Documents folder.
nonisolated enum Persistence {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        let url = documents.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        let url = documents.appendingPathComponent(file)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Persistence save failed for \(file)")
        }
    }

    static func saveImage(_ data: Data, name: String) -> Bool {
        let url = documents.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func imageURL(_ name: String) -> URL {
        documents.appendingPathComponent(name)
    }
}
