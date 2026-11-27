import Foundation
import Testing

/// docs/IOS-TYPOGRAPHY.md: Figma Theme text uses system-font tokens and only two text weights.
struct TypographyStandardTests {
    private static let expectedTokens: Set<String> = [
        "display", "title", "wheel", "headline", "body", "bodyEmphasis", "subheadline",
        "subheadlineEmphasis", "footnote", "footnoteEmphasis", "buttonMedium", "buttonSmall",
        "caption", "captionEmphasis", "micro", "metric"
    ]

    private static func appDirectory() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }   // Tests/GoFlyCoreTests/<file> -> app/GoFly
        return url.appendingPathComponent("App")
    }

    private static func appSources() throws -> [(name: String, lines: [String])] {
        let app = appDirectory()
        let names = try FileManager.default.contentsOfDirectory(atPath: app.path).filter { $0.hasSuffix(".swift") }.sorted()
        return try names.map { name in
            (name, try String(contentsOf: app.appendingPathComponent(name), encoding: .utf8).components(separatedBy: "\n"))
        }
    }

    private static func appSource(named name: String) throws -> String {
        try String(contentsOf: appDirectory().appendingPathComponent(name), encoding: .utf8)
    }

    /// Files whose fixed font sizes are icon or artwork geometry.
    private static let geometryFiles: Set<String> = ["GoFlySymbols.swift", "GoFlyMapCanvas.swift", "GoFlySetupBootstrap.swift",
                                                     "GoFlyOnboardingView.swift", "GoFlyStyle.swift", "GoFlyTypography.swift",
                                                     "GoFlyButtonStyles.swift", "GoFlySharedViews.swift", "GoFlyComponentGallery.swift"]

    @Test func textNeverUsesRawTextStylesOrMediumAndBoldWeights() throws {
        let raw = try NSRegularExpression(pattern: #"\.font\(\.(footnote|body|subheadline|headline|caption2?|title[23]?)\b"#)
        let weights = try NSRegularExpression(pattern: #"\.font\(.*\.weight\(\.(medium|bold|light|heavy)\)"#)
        for source in try Self.appSources() where source.name != "GoFlyTypography.swift" {
            for (index, line) in source.lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                #expect(raw.firstMatch(in: line, range: range) == nil, "\(source.name):\(index + 1) uses a raw text style; use GoFlyFont")
                #expect(weights.firstMatch(in: line, range: range) == nil, "\(source.name):\(index + 1) uses a weight other than regular or semibold")
            }
        }
    }

    @Test func typographyUsesTheSixteenFigmaThemeTokens() throws {
        let source = try Self.appSource(named: "GoFlyTypography.swift")
        guard let start = source.range(of: "enum GoFlyFont: CaseIterable {"),
              let end = source.range(of: "    var pointSize:", range: start.upperBound..<source.endIndex) else {
            Issue.record("GoFlyFont token enum or size table is missing")
            return
        }

        let declarations = source[start.upperBound..<end.lowerBound]
            .replacingOccurrences(of: "case", with: "")
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        #expect(Set(declarations) == Self.expectedTokens)

        let requiredSizeGroups = [
            "case .display: 28", "case .title: 20", "case .wheel: 22",
            "case .headline, .body, .bodyEmphasis: 17", "case .buttonMedium: 16",
            "case .subheadline, .subheadlineEmphasis: 15", "case .buttonSmall: 14",
            "case .footnote, .footnoteEmphasis: 13", "case .caption, .captionEmphasis: 12",
            "case .micro: 10", "case .metric: 36"
        ]
        for group in requiredSizeGroups {
            #expect(source.contains(group), "Missing Figma size mapping: \(group)")
        }

        let requiredDynamicStyles = [
            "case .display: .title", "case .title: .title3", "case .wheel: .title2",
            "case .headline: .headline", "case .body, .bodyEmphasis: .body",
            "case .buttonMedium: .callout", "case .subheadline, .subheadlineEmphasis: .subheadline",
            "case .buttonSmall, .footnote, .footnoteEmphasis: .footnote",
            "case .caption, .captionEmphasis, .micro: .caption", "case .metric: .largeTitle"
        ]
        for group in requiredDynamicStyles {
            #expect(source.contains(group), "Missing Dynamic Type style mapping: \(group)")
        }

        #expect(source.contains("@ScaledMetric private var scaledPointSize: CGFloat"))
        #expect(source.contains("relativeTo: token.dynamicTypeStyle"))
        #expect(source.contains("content.font(.system(size: size, weight: token.weight, design: .default))"))
        #expect(source.contains("var isFixed: Bool { self == .micro || self == .metric }"))
        #expect(source.contains("case .wheel, .body, .subheadline, .footnote, .caption: .regular"))
        #expect(source.contains("default: .semibold"))

        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let documentation = try String(contentsOf: repo.appendingPathComponent("docs/IOS-TYPOGRAPHY.md"), encoding: .utf8)
        for token in Self.expectedTokens {
            #expect(documentation.contains("`\(token)`"), "Typography docs omit \(token)")
        }
    }

    @Test func textColorRolesMapToThemeTokens() throws {
        let source = try Self.appSource(named: "GoFlyTypography.swift")
        guard let start = source.range(of: "enum GoFlyTextColor {") else {
            Issue.record("GoFlyTextColor role map is missing")
            return
        }
        let roles = String(source[start.lowerBound..<source.endIndex])
        let expectedMappings = [
            "static let primary = GoFlyThemeColor.textPrimary",
            "static let secondary = GoFlyThemeColor.textSecondary",
            "static let message = GoFlyThemeColor.textStatusSecondary",
            "static let disabled = GoFlyThemeColor.textDisabled",
            "static let inverse = GoFlyThemeColor.commonWhite",
            "static let onDark = GoFlyThemeColor.commonWhite",
            "static let danger = GoFlyThemeColor.textDanger",
            "static let warning = GoFlyThemeColor.textWarning",
            "static let success = GoFlyThemeColor.textSuccess",
            "static let accent = GoFlyThemeColor.textAccent"
        ]
        for mapping in expectedMappings {
            #expect(roles.contains(mapping), "Missing text color mapping: \(mapping)")
        }
        let targetTokens = expectedMappings.compactMap { $0.split(separator: "=").last.map { $0.trimmingCharacters(in: .whitespaces) } }
        #expect(Set(targetTokens).count == 9, "inverse/onDark must remain aliases of one white token")
    }

    @Test func uiSourcesDoNotSelectCustomFontFamilies() throws {
        let patterns = [
            #"Font\.custom\s*\("#,
            #"\.font\(\s*\.custom\s*\("#,
            #"UIFont\s*\(\s*name\s*:"#,
            #"NSFont\s*\(\s*name\s*:"#,
            #"CTFontCreateWithName\s*\("#
        ]
        let expressions = try patterns.map { try NSRegularExpression(pattern: $0) }
        for source in try Self.appSources() {
            let text = source.lines.joined(separator: "\n")
            let range = NSRange(text.startIndex..., in: text)
            for expression in expressions {
                #expect(expression.firstMatch(in: text, range: range) == nil,
                         "\(source.name) selects a custom font family")
            }
        }
    }

    @Test func textTokensUseTheDynamicTypeModifier() throws {
        let sources = try Self.appSources()
        for source in sources {
            for (index, line) in source.lines.enumerated() {
                #expect(!line.contains(".font(GoFlyFont."),
                         "\(source.name):\(index + 1) applies a token as a fixed Font; use goFlyFont")
            }
        }
        #expect(sources.contains { $0.name == "GoFlyTypography.swift" && $0.lines.contains { $0.contains("content.font(.system(size: size") } })
        #expect(sources.contains { $0.lines.contains { $0.contains(".goFlyFont(GoFlyFont.") } })
    }

    @Test func fixedSizesAppearOnlyNextToIcons() throws {
        for source in try Self.appSources() where !Self.geometryFiles.contains(source.name) {
            for (index, line) in source.lines.enumerated() where line.contains(".font(.system(size:") {
                let context = source.lines[max(0, index - 5)...index].joined(separator: "\n")
                #expect(context.contains("Image(") || context.contains("Canvas") || context.contains("Label("),
                        "\(source.name):\(index + 1) uses a fixed font size outside an icon; use GoFlyFont")
            }
        }
    }

    @Test func textColorsComeFromTheTextColorSet() throws {
        let allowed = ["GoFlyTextColor.", "tone.", "GoFlyStyle.success", "GoFlyStyle.danger", "GoFlyStyle.warning", "foreground)", "(foreground"]
        let raw = try NSRegularExpression(pattern: #"\.foreground(Style|Color)\((\.(primary|secondary|white|black|gray)|Color\.|Color\(|GoFlyStyle\.(primary|secondary|surface|disabledForeground|errorForeground))"#)
        for source in try Self.appSources() where !["GoFlyStyle.swift", "GoFlyTypography.swift", "GoFlyButtonStyles.swift", "GoFlySharedViews.swift", "GoFlySetupBootstrap.swift", "GoFlyComponentGallery.swift"].contains(source.name) {
            for (index, line) in source.lines.enumerated() where line.contains(".foregroundStyle(") || line.contains(".foregroundColor(") {
                let range = NSRange(line.startIndex..., in: line)
                #expect(raw.firstMatch(in: line, range: range) == nil, "\(source.name):\(index + 1) uses a raw color; use GoFlyTextColor")
                #expect(allowed.contains { line.contains($0) }, "\(source.name):\(index + 1) is not a GoFlyTextColor role")
            }
        }
    }
}
