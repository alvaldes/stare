import AppKit
import XCTest

@testable import Stare

/// S6 (round three): "en settings el about tiene un icono que no tiene nada" —
/// the About card's header drew an empty rounded square where its symbol
/// belongs.
///
/// The recorded cause, re-derived on this machine's system list
/// (`CoreGlyphs.bundle/symbol_order.plist`): "app" IS a valid SF Symbol —
/// `NSImage(systemSymbolName:)` answers a real image for it — but the glyph
/// named "app" is ITSELF an empty rounded app-icon tile: its ink is only the
/// tile's outline, with nothing inside. Drawn inside the card's own 24×24
/// control-background tile under its own separator stroke, it reads as a
/// blank rounded square with nothing on it — the screenshot the owner sent.
/// So the rule "no card may carry a name that does not resolve" would go
/// green on exactly this defect; the rule this file pins therefore runs in
/// both directions:
///
/// 1. every `symbol:` argument the Settings sources hand a `SettingsCard`
///    — literal or constant — resolves to a real glyph at the card's own
///    rendering configuration (the walking pin the round asked for: a
///    non-symbol name, which renders nothing at all, can never ship);
/// 2. the About card carries the symbol its sidebar row shows — derived
///    from the pane object (`SettingsArea.about`), so the card and the
///    sidebar row cannot drift apart again, and the empty-tile "app"
///    cannot come back as the About card's glyph.
final class SettingsAboutSymbolTests: XCTestCase {

    /// `Sources/Stare/` in the repository, walked from the test file's
    /// location: `Tests/StareTests/<this file>`.
    private static let settingsSources: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Sources").appendingPathComponent("Stare")
    }()

    /// The files whose `SettingsCard` call sites the walk scans.
    private static let cardFiles = [
        "SettingsView.swift",
        "SettingsComponents.swift",
        "SettingsHistoryPane.swift",
    ]

    /// One card symbol found by the walk: the expression handed to
    /// `SettingsCard(symbol:)`, with the file and line it was read from.
    private struct CardSymbol {
        let file: String
        let line: Int
        /// The whole call-site line the symbol was read from, so a pin can
        /// find one card by its title without re-reading the file.
        let callSite: String
        var expression: String

        /// The symbol name the expression stands for. A literal speaks for
        /// itself; `Self.poolCardSymbol` is the bar's own overflow glyph, kept
        /// one constant from the bar control so the card and the bar cannot
        /// drift — the walk resolves it here instead of re-propagating the
        /// string. Anything else is an expression the walk does not know how
        /// to follow, and the walk must say so: a symbol that reaches a card
        /// through a seam the walk cannot see is exactly the hole this test
        /// exists to close.
        var resolvedName: String? {
            if expression == "Self.poolCardSymbol" { return BarPane.poolCardSymbol }
            // The About card's symbol is DERIVED, not a literal (S6): the
            // pane object's own symbol, the one its sidebar row shows. The
            // walk resolves the expression through the enum itself, so card
            // and sidebar cannot drift even in the walk's own reading.
            if expression == "SettingsArea.about.symbol" { return SettingsArea.about.symbol }
            if expression.hasPrefix("\""), expression.hasSuffix("\"") {
                return String(expression.dropFirst().dropLast())
            }
            return nil
        }
    }

    /// Every `symbol:` argument in the card call sites of the Settings
    /// sources, found the way the compiler reads them: line by line, comment
    /// lines not examples of use. The walk FAILS the test when a
    /// `SettingsCard(` call yields no symbol it could read, so a future card
    /// cannot slip past the resolution pin by writing its symbol in an
    /// unusual shape.
    private static func cardSymbols() throws -> [CardSymbol] {
        var symbols: [CardSymbol] = []
        for file in cardFiles {
            let text = try String(
                contentsOf: settingsSources.appendingPathComponent(file), encoding: .utf8
            )
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if line.contains("SettingsCard("), let range = line.range(of: "symbol:") {
                    let expression = line[range.upperBound...]
                        .trimmingCharacters(in: .whitespaces)
                        .split(separator: ")")
                        .first.map(String.init) ?? ""
                    symbols.append(
                        CardSymbol(file: file, line: index + 1, callSite: line, expression: expression)
                    )
                }
            }
        }
        return symbols
    }

    /// The count of `SettingsCard(` call sites in the same files, so the walk
    /// can prove it saw every card: a call whose symbol the walk missed would
    /// make the counts disagree.
    private static func cardCallCount() throws -> Int {
        var count = 0
        for file in cardFiles {
            let text = try String(
                contentsOf: settingsSources.appendingPathComponent(file), encoding: .utf8
            )
            let lines = text.components(separatedBy: "\n")
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                count += line.components(separatedBy: "SettingsCard(").count - 1
            }
        }
        return count
    }

    func testEverySymbolASettingsCardIsBuiltWithResolvesToARealGlyph() throws {
        let symbols = try Self.cardSymbols()
        let calls = try Self.cardCallCount()
        XCTAssertEqual(
            symbols.count, calls,
            "the walk missed a SettingsCard call site, so a card can be built with a symbol it never verified"
        )
        XCTAssertGreaterThan(
            symbols.count, 0,
            "the walk found no cards at all — the scan is broken, not the symbols"
        )
        for symbol in symbols {
            let name = try XCTUnwrap(
                symbol.resolvedName,
                "\(symbol.file):\(symbol.line) hands a card \(symbol.expression), an expression the walk cannot resolve"
            )
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            XCTAssertNotNil(
                image,
                "\(symbol.file):\(symbol.line) hands a card «\(name)», a name no SF Symbol answers — the header draws nothing there"
            )
            // The card renders at 12 pt semibold; the resolution must survive
            // the exact configuration it is drawn with, and a glyph of no
            // area draws nothing at all.
            let configured = image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            )
            XCTAssertNotNil(configured, "\(symbol.file):\(symbol.line) «\(name)» has no 12 pt semibold variant")
            XCTAssertGreaterThan(
                configured?.size.width ?? -1, 0,
                "\(symbol.file):\(symbol.line) «\(name)» resolves to a glyph with no width, which draws nothing"
            )
        }
    }

    /// The S6 pin in its own words: the About card's symbol is the pane
    /// object's own symbol — the one the sidebar row already shows — so the
    /// card and its sidebar row are one decision, and the empty app tile
    /// ("app", a real SF Symbol whose ink is only the outline of a squircle)
    /// can never be the About header again.
    func testTheAboutCardCarriesTheSymbolItsSidebarRowShows() throws {
        let (name, line) = try Self.aboutCardSymbolAndLine()
        XCTAssertEqual(
            name, SettingsArea.about.symbol,
            "SettingsView.swift:\(line) round three S6: the About card's glyph is not the pane object's own symbol ('\(name)' beside the sidebar's '\(SettingsArea.about.symbol)') — its header drew the empty app tile again"
        )
    }

    /// The (file, line, symbol) of the About card's call site, found by its
    /// title so the pin survives reformatting of the pane below it.
    private static func aboutCardSymbolAndLine() throws -> (name: String, line: Int) {
        let symbols = try cardSymbols().filter { $0.file == "SettingsView.swift" }
        let card = try XCTUnwrap(
            symbols.first { $0.callSite.contains("title: \"Stare\"") },
            "the About card call site is gone from SettingsView.swift"
        )
        let name = try XCTUnwrap(
            card.resolvedName,
            "the About card's symbol is no longer a plain string the walk can read"
        )
        return (name, card.line)
    }
}
