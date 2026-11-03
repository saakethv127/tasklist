import Foundation

public struct CatalogIcon: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let tags: [String]
    public let categories: [String]
    public var storedID: String { "lucide:" + id }
}

public enum IconCatalog {
    public static let all: [CatalogIcon] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "lucide-icons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let icons = try? JSONDecoder().decode([CatalogIcon].self, from: data) else { return [] }
        return icons.sorted { $0.id < $1.id }
    }()
    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.storedID, $0) })
    private static let searchable = all.map { icon in
        (icon: icon, name: normalize(icon.id), text: normalize(([icon.id] + icon.tags + icon.categories).joined(separator: " ")))
    }
    public static func icon(for storedID: String?) -> CatalogIcon? {
        guard let storedID else { return nil }
        return byID[storedID]
    }
    public static func search(_ query: String) -> [CatalogIcon] {
        let normalized = normalize(query)
        let terms = normalized.split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return all }
        return searchable.compactMap { item -> (CatalogIcon, Int)? in
            guard terms.allSatisfy({ item.text.contains($0) }) else { return nil }
            let score = item.name == normalized ? 0 : (item.name.hasPrefix(normalized) ? 1 : (terms.allSatisfy { item.name.contains($0) } ? 2 : 3))
            return (item.icon, score)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.map(\.0)
    }
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
