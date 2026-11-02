import SwiftUI
import UIKit

/// Figma's paste affordance, drawn by the system paste control so iOS does
/// not ask "Allow Paste" on every read. A clear base color is drawn black by
/// the system control, so it takes the search bar's input surface instead.
struct GoFlyPasteButton: View {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var isVisible = true
    let onPaste: (String) -> Void

    var body: some View {
        GoFlySystemPasteControl(accessibilityLabel: accessibilityLabel,
                                accessibilityIdentifier: accessibilityIdentifier,
                                isVisible: isVisible,
                                onPaste: onPaste)
            .frame(width: 44, height: 44)
    }
}

/// Uses the system paste affordance so the clipboard is read only after a direct tap.
struct GoFlySystemPasteControl: UIViewRepresentable {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    /// Hides the view with `isHidden` so the system control stays alive; never use opacity.
    var isVisible = true
    let onPaste: (String) -> Void

    func makeCoordinator() -> PasteReceiver { PasteReceiver(onPaste: onPaste) }

    func makeUIView(context: Context) -> GoFlyPasteAffordanceView {
        let view = GoFlyPasteAffordanceView(target: context.coordinator, accessibilityLabel: accessibilityLabel,
                                            accessibilityIdentifier: accessibilityIdentifier)
        view.isHidden = !isVisible
        return view
    }

    func updateUIView(_ view: GoFlyPasteAffordanceView, context: Context) {
        context.coordinator.onPaste = onPaste
        view.update(target: context.coordinator, accessibilityLabel: accessibilityLabel,
                    accessibilityIdentifier: accessibilityIdentifier)
        view.isHidden = !isVisible
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

    /// A system control that was hidden never draws again once shown; swap in a fresh one.
    override var isHidden: Bool {
        didSet {
            if oldValue, !isHidden, window != nil { rebuildControl() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        refresh()
        rebuildAfterPresentation()
    }

    /// A control created while its page is still sliding in (the full-screen
    /// search cover) sometimes never draws; build a fresh one once it is at rest.
    private func rebuildAfterPresentation() {
        guard let transition = nearestViewController?.transitionCoordinator else { return }
        transition.animate(alongsideTransition: nil) { [weak self] context in
            guard let self, !context.isCancelled, self.window != nil else { return }
            self.rebuildControl()
        }
    }

    private var nearestViewController: UIViewController? {
        var responder = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
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
