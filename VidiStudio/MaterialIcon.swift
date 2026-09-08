import SwiftUI
import CoreText

struct MaterialIcon: View {
    let glyph: String
    private static let registered: Void = {
        if let url = Bundle.main.url(forResource: "MaterialSymbolsRounded", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    var body: some View {
        let _ = Self.registered
        Text(glyph).font(.custom("Material Symbols Rounded", size: 20)).accessibilityHidden(true)
    }
}
