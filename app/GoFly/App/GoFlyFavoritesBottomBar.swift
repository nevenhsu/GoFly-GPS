import SwiftUI
import UIKit

/// Figma D19–D22 bottom area of the favorites pages: the search section
/// (`Bottom bar / 搜尋`, 1 pt divider, 12 pt above and 28 pt below a 48 pt field) and,
/// in multi-select mode, the red delete button *above* it, 12 pt clear of the section.
struct GoFlyFavoritesBottomBar: View {
    /// Search section height without the safe area: 12 + 48 + 28.
    static let searchSectionHeight: CGFloat = 88
    /// A snackbar sits 12 pt above the search section (D22).
    static let snackbarOffset: CGFloat = searchSectionHeight + 12

    let placeholder: String
    @Binding var query: String
    let searchIdentifier: String
    var showsPasteControl = false
    var pasteIdentifier = "favorites.searchPaste"
    var onPaste: (String) -> Void = { _ in }
    /// Non-nil only while selecting: the delete button title.
    var deleteTitle: String? = nil
    var deleteEnabled = true
    var deleteIdentifier = "favorites.deleteSelected"
    var onDelete: () -> Void = { }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let deleteTitle {
                Button(action: onDelete) {
                    HStack(spacing: 8) {
                        GoFlyTrashIcon(size: 17)
                        Text(deleteTitle)
                    }
                }
                .buttonStyle(GoFlyActionStyle(destructive: true, fixedHeight: 48))
                .disabled(!deleteEnabled)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier(deleteIdentifier)
            }
            searchSection
        }
    }

    private var searchSection: some View {
        HStack(spacing: 8) {
            GoFlyIcon(GoFlySymbols.search)
                .goFlyIconSize(size: 17)
                .foregroundStyle(GoFlyTextColor.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($focused)
                .accessibilityIdentifier(searchIdentifier)
            if query.isEmpty, showsPasteControl {
                GoFlySystemPasteControl(
                    accessibilityLabel: goFlyString("search.paste"),
                    accessibilityIdentifier: pasteIdentifier,
                    onPaste: onPaste
                )
                .frame(width: 44, height: 44)
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    GoFlyIcon(.close)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("search.clear"))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, showsPasteControl ? 0 : 16)
        .frame(minHeight: 48)
        .goFlySearchField(isFocused: focused)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(GoFlyStyle.tabBarSurface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { GoFlyStyle.tabSeparator.frame(height: 1) }
    }
}

/// Uses the system paste affordance so the clipboard is read only after a direct tap.
struct GoFlySystemPasteControl: UIViewRepresentable {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onPaste: (String) -> Void

    func makeCoordinator() -> PasteReceiver { PasteReceiver(onPaste: onPaste) }

    func makeUIView(context: Context) -> GoFlyPasteAffordanceView {
        GoFlyPasteAffordanceView(target: context.coordinator, accessibilityLabel: accessibilityLabel,
                                 accessibilityIdentifier: accessibilityIdentifier)
    }

    func updateUIView(_ view: GoFlyPasteAffordanceView, context: Context) {
        context.coordinator.onPaste = onPaste
        view.update(target: context.coordinator, accessibilityLabel: accessibilityLabel,
                    accessibilityIdentifier: accessibilityIdentifier)
    }

    @MainActor
    final class PasteReceiver: NSObject, UIPasteConfigurationSupporting {
        var pasteConfiguration: UIPasteConfiguration? = UIPasteConfiguration(forAccepting: String.self)
        var onPaste: (String) -> Void

        init(onPaste: @escaping (String) -> Void) { self.onPaste = onPaste }

        func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.canLoadObject(ofClass: String.self) }
        }

        func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return }
            let _ = provider.loadObject(ofClass: String.self) { [weak self] pasted, _ in
                guard let pasted else { return }
                Task { @MainActor [weak self] in self?.onPaste(pasted) }
            }
        }
    }
}

/// The paste affordance inside a search field. The system paste control (no
/// "Allow Paste" prompt) is always shown, dimmed by iOS while the clipboard
/// has no text. No custom icon sits underneath: it would show through the
/// dimmed system control as a doubled glyph.
final class GoFlyPasteAffordanceView: UIView {
    private var control: UIPasteControl
    private weak var target: (any UIPasteConfigurationSupporting)?
    private var accessibilityIdentifierValue: String

    init(target: any UIPasteConfigurationSupporting, accessibilityLabel: String, accessibilityIdentifier: String) {
        control = UIPasteControl(configuration: UIPasteControl.Configuration())
        accessibilityIdentifierValue = accessibilityIdentifier
        super.init(frame: .zero)
        clipsToBounds = true
        self.accessibilityLabel = accessibilityLabel
        self.target = target
        rebuildControl()
        // The system control resolves its colors once; rebuild it for the new appearance.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GoFlyPasteAffordanceView, _: UITraitCollection) in
            view.rebuildControl()
        }
        for name in [UIPasteboard.changedNotification, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
    }

    private func pin(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func rebuildControl() {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = GoFlyStyle.pasteSymbolUIColor.resolvedColor(with: traitCollection)
        // A clear base color is drawn black by the system control; match the field's surface.
        configuration.baseBackgroundColor = GoFlyStyle.inputSurfaceUIColor.resolvedColor(with: traitCollection)
        control.removeFromSuperview()
        control = UIPasteControl(configuration: configuration)
        pin(control)
        update(target: target, accessibilityLabel: accessibilityLabel ?? "",
               accessibilityIdentifier: accessibilityIdentifierValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { refresh() }
    }

    func update(target: (any UIPasteConfigurationSupporting)?, accessibilityLabel: String, accessibilityIdentifier: String) {
        self.target = target
        self.accessibilityLabel = accessibilityLabel
        accessibilityIdentifierValue = accessibilityIdentifier
        control.target = target
        control.accessibilityLabel = accessibilityLabel
        control.accessibilityIdentifier = accessibilityIdentifier
        refresh()
    }

    @objc private func refresh() {
        // The system control is always shown; iOS dims it while the clipboard has no text.
        control.isHidden = false
    }
}
