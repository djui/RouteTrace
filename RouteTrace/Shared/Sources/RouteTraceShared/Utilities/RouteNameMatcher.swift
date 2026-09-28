import Foundation

/// Finds routes by what someone said or typed, for Siri and Shortcuts.
///
/// Matching ignores case, accents and punctuation, so "sormland gravel" finds "Sörmland Gravel".
public enum RouteNameMatcher {
    /// Matching routes, best first: the whole name, then names starting with the query, then
    /// names containing it, then names containing each of its words. Ties keep the input order.
    public static func matches<Route>(_ query: String, in routes: [Route], name: (Route) -> String) -> [Route] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        let words = needle.split(separator: " ")

        let scored: [(offset: Int, score: Int, route: Route)] = routes.enumerated().compactMap { offset, route in
            let haystack = normalized(name(route))
            let score: Int
            if haystack == needle {
                score = 0
            } else if haystack.hasPrefix(needle) {
                score = 1
            } else if haystack.contains(needle) {
                score = 2
            } else if words.allSatisfy({ haystack.contains($0) }) {
                score = 3
            } else {
                return nil
            }
            return (offset, score, route)
        }
        return scored
            .sorted { ($0.score, $0.offset) < ($1.score, $1.offset) }
            .map(\.route)
    }

    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }
}
