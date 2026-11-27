import SwiftUI
import AppKit

enum GoFlyStyle {
    // MARK: - Text
    static let ink = MacColorSystem.primaryText
    static let muted = MacColorSystem.secondaryText
    static let disabled = MacColorSystem.disabledText

    // MARK: - Surfaces
    static let sidebar = MacColorSystem.sidebar
    static let canvas = MacColorSystem.canvas
    static let surface = MacColorSystem.surface
    static let secondarySurface = MacColorSystem.controlSurface
    static let disabledSurface = MacColorSystem.disabledSurface
    static let inputSurface = MacColorSystem.inputSurface

    // MARK: - Borders & Separators
    static let line = MacColorSystem.separator
    static let border = MacColorSystem.border
    static let inputBorder = MacColorSystem.inputBorder

    // MARK: - Status
    static let success = MacColorSystem.success
    static let warning = MacColorSystem.warning
    static let error = MacColorSystem.error

    // MARK: - Radius, Spacing & Typography
    enum Radius {
        static let control: CGFloat = 10
        static let inset: CGFloat = 12
        static let card: CGFloat = 16
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    static let cornerRadius: CGFloat = Radius.card

    enum Typography {
        static let display = font(28, bold: true)
        static let title = font(17, bold: true)
        static let headline = font(14, bold: true)
        static let body = font(13)
        static let bodyEmphasis = font(13, bold: true)
        static let footnote = font(12)
        static let footnoteEmphasis = font(12, bold: true)
        static let caption = font(11)
        static let captionEmphasis = font(11, bold: true)
        static let micro = font(10, bold: true)
    }

    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .semibold : .regular)
    }
}

enum GoFlyMacSymbols {
    static let home = "house"
    static let environment = "checklist"
    static let device = "iphone"
    static let install = "square.and.arrow.down"
    static let signing = "signature"
    static let repair = "wrench.and.screwdriver"
    static let connection = "network"
    static let completed = "checkmark.circle.fill"
    static let reinstall = "arrow.triangle.2.circlepath"
    static let usb = "cable.connector"
    static let wifi = "wifi"
}

private struct GoFlyInset: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(GoFlyStyle.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.Radius.inset, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: GoFlyStyle.Radius.inset, style: .continuous).strokeBorder(GoFlyStyle.line, lineWidth: 0.5) }
    }
}

private struct GoFlyInput: ViewModifier {
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.textFieldStyle(.plain)
            .font(GoFlyStyle.Typography.body)
            .padding(.horizontal, GoFlyStyle.Spacing.md).padding(.vertical, 10)
            .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous)
                    .strokeBorder(focused ? GoFlyStyle.ink : GoFlyStyle.inputBorder, lineWidth: focused ? 1.5 : 0.75)
                    .allowsHitTesting(false)
            }
            .focused($focused)
            .opacity(isEnabled ? 1 : 0.6)
    }
}

extension View {
    func goFlyInput() -> some View { modifier(GoFlyInput()) }
    func goFlyInset() -> some View { modifier(GoFlyInset()) }
    /// Draws the hover/focus ring in the control's own shape, so it follows a
    /// capsule button or a row's corner radius instead of a fixed rectangle.
    func goFlyRowFocus<S: InsettableShape>(_ shape: S) -> some View { modifier(GoFlyRowFocus(shape: shape)) }
    func goFlyRowFocus() -> some View { goFlyRowFocus(RoundedRectangle(cornerRadius: GoFlyStyle.Radius.inset, style: .continuous)) }
}

private struct GoFlyRowFocus<S: InsettableShape>: ViewModifier {
    let shape: S
    @FocusState private var focused: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.focused($focused)
            .overlay {
                // A negative inset grows the shape concentrically, so the
                // focused ring keeps the same rounding just outside the edge.
                shape.inset(by: focused ? -3 : 0)
                    .strokeBorder(focused ? GoFlyStyle.ink : GoFlyStyle.line,
                                  lineWidth: focused ? 2 : 1)
                    .opacity(isEnabled && (focused || hovered) ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}

struct DesignAsset: View {
    let name: String
    let size: CGSize
    let tint: Color
    init(_ name: String, width: CGFloat, height: CGFloat? = nil, tint: Color = GoFlyStyle.ink) {
        self.name = name
        self.size = CGSize(width: width, height: height ?? width)
        self.tint = tint
    }
    var body: some View {
        if let symbol = symbol {
            Image(systemName: symbol)
                .font(.system(size: min(size.width, size.height) * 0.78, weight: .regular))
                .frame(width: size.width, height: size.height)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        } else if let url = Bundle.module.url(forResource: name, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().renderingMode(.template).aspectRatio(contentMode: .fit)
                .frame(width: name == "WingedArrow" ? size.width * (232.0 / 360.0) : size.width,
                       height: name == "WingedArrow" ? size.height * (188.0 / 360.0) : size.height)
                .frame(width: size.width, height: size.height).foregroundStyle(tint).accessibilityHidden(true)
        }
    }

    private var symbol: String? {
        switch name {
        case "Device": GoFlyMacSymbols.device
        case "USB": GoFlyMacSymbols.usb
        case "EnvironmentPassed": GoFlyMacSymbols.completed
        default: nil
        }
    }
}

private struct GoFlyMacButtonStyle: ButtonStyle {
    let primary: Bool
    let focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? (primary ? MacColorSystem.primaryActionText : GoFlyStyle.ink) : GoFlyStyle.disabled)
            .background(isEnabled && primary ? MacColorSystem.primaryActionSurface : GoFlyStyle.secondarySurface,
                        in: RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous)
                    .strokeBorder(focused ? GoFlyStyle.ink : GoFlyStyle.line, lineWidth: focused ? 2 : 0.75)
                    .padding(focused ? -3 : 0)
                    .allowsHitTesting(false)
            }
            .opacity(!isEnabled ? 0.6 : configuration.isPressed ? 0.72 : hovered ? 0.86 : 1)
            .onHover { hovered = $0 }
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    var width: CGFloat? = 208
    var height: CGFloat = 36
    var enabled = true
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            Text(title).font(GoFlyStyle.font(13, bold: true))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: height)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(GoFlyMacButtonStyle(primary: primary, focused: focused))
        .disabled(!enabled).focused($focused).frame(width: width)
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(GoFlyStyle.font(14, bold: true)).foregroundStyle(GoFlyStyle.ink)
            Text(detail).font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 200, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius).strokeBorder(GoFlyStyle.line, lineWidth: 0.75))
    }
}

struct Rule: View { var body: some View { Rectangle().fill(GoFlyStyle.line).frame(height: 1) } }
