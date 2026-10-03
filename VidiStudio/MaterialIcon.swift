import SwiftUI
import CoreText
import AppKit

struct MaterialIcon: View {
    let glyph: String
    var size: CGFloat = 20
    private static let registered: Void = {
        if let url = Bundle.main.url(forResource: "MaterialSymbolsRounded", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    private static var menuImages: [String: NSImage] = [:]

    @MainActor
    static func menuImage(glyph: String) -> NSImage {
        if let image = menuImages[glyph] { return image }
        let _ = Self.registered
        let font = NSFont(name: "Material Symbols Rounded", size: 18) ?? NSFont.systemFont(ofSize: 18)
        let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.black])
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        menuImages[glyph] = image
        return image
    }

    var body: some View {
        let _ = Self.registered
        Text(glyph).font(.custom("Material Symbols Rounded", size: size)).accessibilityHidden(true)
    }
}
