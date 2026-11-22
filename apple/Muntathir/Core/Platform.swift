import SwiftUI

// Small bridges so shared views compile for both iOS and native macOS.

#if canImport(UIKit)
    import UIKit

    typealias PlatformColor = UIColor
    typealias PlatformFont = UIFont
    typealias PlatformImage = UIImage
#else
    import AppKit

    typealias PlatformColor = NSColor
    typealias PlatformFont = NSFont
    typealias PlatformImage = NSImage

    extension NSColor {
        static var label: NSColor {
            .labelColor
        }
    }

    extension NSFont {
        var lineHeight: CGFloat {
            ceil(ascender - descender + leading)
        }
    }

    extension EnvironmentValues {
        /// Mac windows always lay out like a regular-width iPad.
        var horizontalSizeClass: UserInterfaceSizeClass? {
            .regular
        }
    }
#endif

extension Color {
    static var groupedBackground: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(.systemGroupedBackground)
        #endif
    }

    static var secondaryGroupedBackground: Color {
        #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #else
            Color(.secondarySystemGroupedBackground)
        #endif
    }
}

enum Clipboard {
    static func copy(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The iOS navigation bar's trailing edge; the primary toolbar area on macOS.
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .primaryAction
        #endif
    }

    /// The iOS navigation bar's leading edge; the navigation area on macOS.
    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .navigation
        #endif
    }
}

extension SearchFieldPlacement {
    /// A search field that stays visible below the navigation bar on iOS, and in the toolbar on macOS.
    static var alwaysVisible: SearchFieldPlacement {
        #if os(iOS)
            .navigationBarDrawer(displayMode: .always)
        #else
            .automatic
        #endif
    }
}

extension View {
    /// Inline navigation titles are an iOS concept; macOS shows titles in the window toolbar.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    func groupedListStyle() -> some View {
        #if os(iOS)
            listStyle(.insetGrouped)
        #else
            listStyle(.inset)
        #endif
    }
}

extension PlatformFont {
    /// The same face with bold or italic applied, keeping the original face when it has no such variant.
    func with(bold: Bool, italic: Bool = false, size: CGFloat) -> PlatformFont {
        #if os(macOS)
            var traits: NSFontDescriptor.SymbolicTraits = []
            if bold {
                traits.insert(.bold)
            }
            if italic {
                traits.insert(.italic)
            }
            return NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: size) ?? withSize(size)
        #else
            var traits: UIFontDescriptor.SymbolicTraits = []
            if bold {
                traits.insert(.traitBold)
            }
            if italic {
                traits.insert(.traitItalic)
            }
            return UIFont(descriptor: fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor, size: size)
        #endif
    }
}
