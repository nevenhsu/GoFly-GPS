import GoFlyCore
import SwiftUI
import UIKit

/// Shared full-screen search used by teleport and by route fields (plan 4.3 / 4.7).
///
/// The header belongs to the page: a back chevron next to the field, with no
/// navigation title, so the keyboard never pushes a title bar around. Results
/// are an unframed list of 64 pt rows with an icon tile, a title and one
/// subtitle line; the field keeps its own gray, bordered appearance.
struct GoFlySearchPanel: View {
    @ObservedObject var search: CandidateController
    var focusRequest: UUID?
    var placeholderKey: String = "search.placeholder"
    var placeholderOverride: String?
    var accessibilityLabelOverride: String?
    /// Optional chip such as "Choosing: destination" for route fields.
    var roleTitle: String?
    var onBack: (() -> Void)?
    var onFavorites: () -> Void = {}
    var recentPlaces: [MapPlace] = []
    var fixtureCoordinateResult: MapPlace? = nil
    var fixtureNearbyResults: [MapPlace]? = nil
    var onClearRecentPlaces: (() -> Void)?
    var onSelect: (MapPlace) -> Void = { _ in }
    var onUseCurrentLocation: (() -> Void)?
    var onClearPlace: (() -> Void)?
    @EnvironmentObject private var favorites: FavoritePlacesStore
    @State private var focused = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if let roleTitle { roleChip(roleTitle) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if search.isSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(goFlyString("search.searching"))
                                .goFlyFont(GoFlyFont.subheadline)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .accessibilityIdentifier("search.searching")
                    }
                    content
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .goFlyToastOverlay(topInset: 72) {
            if let error = search.inputError {
                GoFlyStatusBanner(tone: .warning, title: goFlyIssueTitle(for: error.rawValue), message: goFlyString(error.rawValue),
                                  identifier: "search.inputError")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.panel")
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, request in if request != nil { focused = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    GoFlyIcon(.chevronLeft)
                        .goFlyIconSize(size: 18)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(GoFlyTextColor.primary)
                .accessibilityLabel(goFlyString("common.back"))
                .accessibilityIdentifier("search.back")
                .padding(.leading, -8)
            }
            HStack(spacing: 8) {
                GoFlyIcon(GoFlySymbols.search)
                    .goFlyIconSize(size: 17)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .accessibilityHidden(true)
                PasteableSearchTextField(
                    placeholder: placeholderOverride ?? goFlyString(placeholderKey),
                    accessibilityLabel: accessibilityLabelOverride
                        ?? (placeholderOverride?.isEmpty == false
                            ? placeholderOverride! : goFlyString(placeholderKey)),
                    text: search.query,
                    isFocused: focused,
                    onTextChange: { query in
                        search.updateQuery(query)
                        focused = true
                    },
                    onFocusChange: { focused = $0 },
                    onSubmit: { focused = false }
                )
                .frame(maxWidth: .infinity, minHeight: 48)
                .frame(height: 48)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .goFlySearchField(isFocused: focused)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        // Search bar to the first object below it: 12 pt on B3, B4 and D5.
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func roleChip(_ title: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                GoFlyIcon(GoFlySymbols.flag)
                    .goFlyIconSize(size: 12, maximum: 14)
                Text(title)
                    .goFlyFont(GoFlyFont.footnote)
            }
            .foregroundStyle(GoFlyTextColor.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(GoFlyStyle.secondarySurface, in: Capsule())
            Spacer()
            Button(action: onFavorites) {
                GoFlyIconLabel(title: goFlyString("favorites.shortTitle"), icon: .star,
                               iconSize: 22, spacing: 8)
                    .lineLimit(1)
            }
            .buttonStyle(GoFlyButtonStyle(variant: .ghostPrimary, size: .inline, expandsToFill: false))
            .accessibilityLabel(goFlyString("favorites.shortTitle"))
            .accessibilityIdentifier("search.favorites")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.role")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if search.queryKind == .empty {
            emptyContent
        } else {
            resultsContent
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if let onUseCurrentLocation {
            actionRow(goFlyString("route.useCurrentLocation"),
                      symbol: GoFlySymbols.location, identifier: "route.picker.current",
                      action: onUseCurrentLocation)
                .padding(.bottom, 16)
        }
        if !recentPlaces.isEmpty {
            sectionHeader("search.recent",
                          actionTitle: goFlyString("search.clearHistory"),
                          actionIdentifier: "search.clearHistory",
                          action: onClearRecentPlaces)
            VStack(spacing: 0) {
                ForEach(Array(recentPlaces.enumerated()), id: \.element.id) { index, place in
                    recentRow(place, title: place.title,
                              showsSeparator: index < recentPlaces.count - 1)
                }
            }
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
        // An empty query has not searched anything, so it never reports "no results" (B3).
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let fixtureCoordinateResult {
            coordinateCard(fixtureCoordinateResult)
        } else if search.queryKind == .coordinate, let coordinate = search.results.first {
            coordinateCard(coordinate)
        }
        if !matchingFavorites.isEmpty {
            sectionHeader("favorites.title")
            ForEach(matchingFavorites) { favorite in
                row(favorite.place, title: favorite.displayTitle,
                    symbol: GoFlySymbols.favoriteSelected, identifier: favorite.place)
            }
        }
        // A coordinate query already owns the first row; never render it twice.
        let places = fixtureNearbyResults ?? (search.queryKind == .coordinate ? [] : search.results.filter { place in
            !matchingFavorites.contains { $0.place.coordinate == place.coordinate }
        })
        if !places.isEmpty {
            sectionHeader("search.nearby")
            VStack(spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    placeRow(place, identifier: place, showsSeparator: index < places.count - 1)
                }
            }
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("search.nearby.card")
        }
        if places.isEmpty, matchingFavorites.isEmpty, search.queryKind != .coordinate,
           !search.isSearching, search.inputError == nil {
            GoFlyEmptyState(symbol: GoFlySymbols.search,
                            message: goFlyString(search.searchFailed ? "search.failed" : "search.noResults"))
                .padding(.top, 12)
                .accessibilityIdentifier("search.emptyResults")
        }
    }

    private var matchingFavorites: [FavoritePlace] {
        guard fixtureNearbyResults == nil, search.queryKind == .name else { return [] }
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return favorites.favorites.filter {
            ($0.label?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.place.title.localizedCaseInsensitiveContains(query)
                || ($0.place.address?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Rows

    private func sectionHeader(_ key: String, actionTitle: String? = nil,
                               actionIdentifier: String? = nil,
                               action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(goFlyString(key))
                .goFlyFont(GoFlyFont.subheadlineEmphasis)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        // Keep the 44 pt hit area without growing the header,
                        // so the label stays 8 pt above the list.
                        .padding(.vertical, -12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(actionIdentifier ?? (key == "favorites.title" ? "favorites.open" : "search.sectionAction.\(key)"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, key == "search.recent" ? 0 : (key == "search.nearby" ? 16 : 8))
        .padding(.bottom, key == "search.recent" || key == "search.nearby" ? 8 : 4)
        .accessibilityIdentifier("search.section.\(key)")
    }

    private func coordinateCard(_ place: MapPlace) -> some View {
        coordinateRow(place)
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("search.coordinateCard")
    }

    private func coordinateRow(_ place: MapPlace) -> some View {
        GoFlyListRow(minimumHeight: 64) {
            Button {
                select(place)
            } label: {
                HStack(spacing: 20) {
                    GoFlyIcon(GoFlySymbols.heading)
                        .goFlyIconSize(size: 16)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goFlyLocalizedFormat(goFlyString("search.goToCoordinate"),
                                                  place.coordinate.shortDisplayText))
                            .goFlyFont(GoFlyFont.bodyEmphasis)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(goFlyString("search.validCoordinate"))
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.result.\(place.coordinate.displayText)")
        }
    }

    private func placeRow(_ place: MapPlace, identifier: MapPlace,
                          showsSeparator: Bool = true) -> some View {
        GoFlyListRow(minimumHeight: 64, separatorLeadingInset: showsSeparator ? 60 : nil) {
            Button {
                select(place)
            } label: {
                HStack(spacing: 20) {
                    GoFlyIcon(GoFlySymbols.place)
                        .goFlyIconSize(size: 16)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.title)
                            .goFlyFont(GoFlyFont.body)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(place.address ?? place.coordinate.displayText)
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.result.\(identifier.coordinate.displayText)")
        }
    }

    private func recentRow(_ place: MapPlace, title: String?, showsSeparator: Bool) -> some View {
        GoFlyListRow(minimumHeight: 52, separatorLeadingInset: showsSeparator ? 60 : nil) {
            Button {
                select(place)
            } label: {
                HStack(spacing: 20) {
                    GoFlyIcon(GoFlySymbols.recent)
                        .goFlyIconSize(size: 16)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(title?.isEmpty == false ? title! : place.title)
                        .goFlyFont(GoFlyFont.body)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.result.\(place.coordinate.displayText)")
        }
    }

    private func row(_ place: MapPlace, title: String? = nil, symbol: GoFlyIconAsset,
                     identifier: MapPlace) -> some View {
        GoFlyListRow(minimumHeight: 64, separatorLeadingInset: 68) {
            Button {
                select(place)
            } label: {
                HStack(spacing: 12) {
                    iconTile(symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title?.isEmpty == false ? title! : place.title)
                            .goFlyFont(GoFlyFont.body)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(place.address ?? place.coordinate.displayText)
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.result.\(identifier.coordinate.displayText)")
        }
    }

    private func actionRow(_ title: String, symbol: GoFlyIconAsset, identifier: String,
                           action: @escaping () -> Void) -> some View {
        GoFlyListRow(minimumHeight: 52) {
            Button {
                focused = false
                action()
            } label: {
                HStack(spacing: 20) {
                    GoFlyIcon(symbol)
                        .goFlyIconSize(size: 16)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(title)
                        .goFlyFont(GoFlyFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        }
        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    /// A calm gray icon tile keeps titles aligned across sections, matching the
    /// Figma list instead of a bare glyph.
    private func iconTile(_ symbol: GoFlyIconAsset, filled: Bool = false) -> some View {
        GoFlyIcon(symbol)
            .goFlyIconSize(size: 14)
            .foregroundStyle(filled ? GoFlyTextColor.inverse : GoFlyTextColor.primary)
            .frame(width: 36, height: 36)
            .background(filled ? GoFlyStyle.primary : GoFlyStyle.secondarySurface, in: Circle())
            .accessibilityHidden(true)
    }

    private func select(_ place: MapPlace) {
        search.select(place)
        focused = false
        onSelect(place)
    }
}

/// A native text field keeps standard cursor and selection behavior while its
/// right-side controls provide clear and privacy-safe system paste actions.
private struct PasteableSearchTextField: UIViewRepresentable {
    let placeholder: String
    let accessibilityLabel: String
    let text: String
    let isFocused: Bool
    let onTextChange: (String) -> Void
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onFocusChange: onFocusChange, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .none
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = GoFlyStyle.primaryTextUIColor
        textField.tintColor = GoFlyStyle.accentTextUIColor
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .search
        textField.clearButtonMode = .never
        textField.pasteConfiguration = UIPasteConfiguration(forAccepting: String.self)
        textField.accessibilityIdentifier = "search.query"
        textField.accessibilityLabel = accessibilityLabel
        textField.delegate = context.coordinator
        textField.pasteDelegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

        let controls = SearchTextFieldAccessoryView()
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)

        let pasteReceiver = GoFlySystemPasteControl.PasteReceiver { [weak textField] pasted in
            let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            textField?.text = trimmed
            textField?.sendActions(for: .editingChanged)
        }
        let pasteButton = GoFlyPasteAffordanceView(target: pasteReceiver,
                                                   accessibilityLabel: goFlyString("search.paste"),
                                                   accessibilityIdentifier: "search.paste")
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(pasteButton)
        NSLayoutConstraint.activate([
            pasteButton.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            pasteButton.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            pasteButton.topAnchor.constraint(equalTo: controls.topAnchor),
            pasteButton.bottomAnchor.constraint(equalTo: controls.bottomAnchor)
        ])

        let clearButton = UIButton(type: .system)
        clearButton.setImage(GoFlyIcon.uiImage(GoFlySymbols.clearSearch), for: .normal)
        clearButton.tintColor = GoFlyStyle.pasteSymbolUIColor
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clearButton.widthAnchor.constraint(equalToConstant: 44),
            clearButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        clearButton.accessibilityLabel = goFlyString("search.clear")
        clearButton.accessibilityIdentifier = "search.clear"
        clearButton.addAction(UIAction { [weak textField] _ in
            textField?.text = ""
            textField?.sendActions(for: .editingChanged)
            textField?.becomeFirstResponder()
        }, for: .touchUpInside)
        controls.addSubview(clearButton)
        NSLayoutConstraint.activate([
            clearButton.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            clearButton.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            clearButton.topAnchor.constraint(equalTo: controls.topAnchor),
            clearButton.bottomAnchor.constraint(equalTo: controls.bottomAnchor)
        ])
        textField.rightView = controls
        textField.rightViewMode = .always
        textField.text = text
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: GoFlyStyle.inputTextUIColor]
        )
        context.coordinator.clearButton = clearButton
        context.coordinator.pasteButton = pasteButton
        context.coordinator.pasteReceiver = pasteReceiver
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onSubmit = onSubmit
        clearButton.isHidden = text.isEmpty
        pasteButton.isHidden = !text.isEmpty
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: GoFlyStyle.inputTextUIColor]
        )
        if textField.text != text { textField.text = text }
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onSubmit = onSubmit
        context.coordinator.clearButton?.isHidden = text.isEmpty
        context.coordinator.pasteButton?.isHidden = !text.isEmpty

        if isFocused, !textField.isFirstResponder {
            DispatchQueue.main.async { [weak textField] in _ = textField?.becomeFirstResponder() }
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UITextPasteDelegate {
        var onTextChange: (String) -> Void
        var onFocusChange: (Bool) -> Void
        var onSubmit: () -> Void
        weak var clearButton: UIButton?
        weak var pasteButton: UIView?
        /// UIPasteControl holds its target weakly.
        var pasteReceiver: GoFlySystemPasteControl.PasteReceiver?

        init(onTextChange: @escaping (String) -> Void,
             onFocusChange: @escaping (Bool) -> Void,
             onSubmit: @escaping () -> Void) {
            self.onTextChange = onTextChange
            self.onFocusChange = onFocusChange
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            let value = textField.text ?? ""
            clearButton?.isHidden = value.isEmpty
            pasteButton?.isHidden = !value.isEmpty
            onTextChange(value)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) { onFocusChange(true) }
        func textFieldDidEndEditing(_ textField: UITextField) { onFocusChange(false) }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return false
        }

        func textPasteConfigurationSupporting(
            _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
            combineItemAttributedStrings itemStrings: [NSAttributedString],
            for textRange: UITextRange
        ) -> NSAttributedString {
            trimmedPasteText(itemStrings)
        }
    }
}

private final class SearchTextFieldAccessoryView: UIView {
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
}

private func trimmedPasteText(_ itemStrings: [NSAttributedString]) -> NSAttributedString {
    let pastedText = itemStrings.map(\.string).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    return NSAttributedString(string: pastedText)
}
