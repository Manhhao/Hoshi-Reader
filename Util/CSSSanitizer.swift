import Foundation

struct CSSSanitizer {
    private static let calibreRule = /(?ms)^(\s*\.(?:calibre\d*|body|c\d*|p\d+)\s*)\{(.*?)\}/
    private static let writingModeProperties: Set<String> = [
        "writing-mode", "-webkit-writing-mode", "-epub-writing-mode",
    ]
    
    static func sanitizeDirectory(_ directory: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "css" {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let sanitized = sanitizeCSS(content)
            if sanitized != content {
                try? sanitized.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    static func sanitizeCSS(_ css: String) -> String {
        var didStripLineHeight = false
        let result = css.replacing(calibreRule) { match in
            let declarations = match.2.split(separator: ";", omittingEmptySubsequences: false)
            if declarations.contains(where: { propertyName(of: $0) == "line-height" }) {
                didStripLineHeight = true
            }
            let stripHeight = declarations.contains { writingModeProperties.contains(propertyName(of: $0)) }
            let cleaned = declarations
                .compactMap { sanitizeDeclaration($0, stripHeight: stripHeight) }
                .joined(separator: ";")
            return "\(match.1){\(cleaned)}"
        }
        return didStripLineHeight ? result + "\nbody { line-height: 1.65; }\n" : result
    }
    
    private static func sanitizeDeclaration(_ declaration: Substring, stripHeight: Bool) -> String? {
        switch propertyName(of: declaration) {
        case let name where writingModeProperties.contains(name):
            return nil
        case "line-height":
            return nil
        case "height" where stripHeight:
            return nil
        case "text-indent":
            let value = declaration.drop { $0 != ":" }.dropFirst()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.hasPrefix("-") ? String(declaration) : " text-indent: 0"
        default:
            return String(declaration)
        }
    }
    
    private static func propertyName(of declaration: Substring) -> String {
        declaration.prefix { $0 != ":" }
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
