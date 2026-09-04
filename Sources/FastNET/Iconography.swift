import AppKit
import SwiftUI

/// A shared SF Symbols vocabulary for the menu bar, popover and profile editor.
enum FastNETSymbol {
    /// Deliberately avoids the system Wi-Fi glyph so FastNET is easy to spot
    /// beside Control Center and the built-in Wi-Fi status item.
    static let menuBarConnected = "arrow.left.arrow.right.circle.fill"
    static let menuBarDisconnected = "arrow.left.arrow.right.circle"
    static let connected = "wifi"
    static let disconnected = "wifi.slash"
    static let profile = "slider.horizontal.3"
    static let networkProfile = "wifi.circle.fill"
    static let automatic = "bolt.fill"
    static let manualIPv4 = "number.square"
    static let dns = "globe"
    static let success = "checkmark.circle.fill"
    static let warning = "exclamationmark.triangle.fill"
    static let refresh = "arrow.clockwise"
    static let settings = "gearshape"
    static let more = "ellipsis.circle"
}

struct FastNETBrandIcon: View {
    var size: CGFloat = 42

    var body: some View {
        if let image = NSImage.fastNETAppIcon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.blue.gradient)
                Image(systemName: FastNETSymbol.connected)
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

private extension NSImage {
    static var fastNETAppIcon: NSImage? {
        guard let url = Bundle.module.url(forResource: "FastNET-AppIcon-Master", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
