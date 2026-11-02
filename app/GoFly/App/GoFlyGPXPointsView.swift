import GoFlyCore
import SwiftUI

/// GPX samples retain their original order; tapping only changes the map camera.
struct GoFlyGPXPointList: View {
    let points: [GeoCoordinate]
    var summarized = false
    var onFocus: (GeoCoordinate) -> Void
    var onShowAll: () -> Void = {}

    var body: some View {
        // Summarized is at most five rows inside the self-sizing route panel: a lazy stack reports a stale
        // height on first layout after launch and clips the Cancel / Start row against the tab bar.
        listContent
        .background(summarized ? GoFlyStyle.secondarySurface : GoFlyStyle.cardSurface,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.border, lineWidth: 0.5) }
        .accessibilityIdentifier("imports.points.list")
    }

    @ViewBuilder private var listContent: some View {
        if summarized { VStack(spacing: 0) { rows } } else { LazyVStack(spacing: 0) { rows } }
    }

    @ViewBuilder private var rows: some View {
        Group {
            if summarized && points.count > 10 {
                GoFlyListRow(minimumHeight: 46, separatorLeadingInset: 16, separatorTrailingInset: 16) { pointRow(0, compact: true) }
                GoFlyListRow(minimumHeight: 46, separatorLeadingInset: 16, separatorTrailingInset: 16) { pointRow(1, compact: true) }
                GoFlyListRow(minimumHeight: 44, separatorLeadingInset: 16, separatorTrailingInset: 16) {
                    Text(goFlyLocalizedFormat(goFlyString("imports.points.middle"), points.count - 3))
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                }
                GoFlyListRow(minimumHeight: 46, separatorLeadingInset: 16, separatorTrailingInset: 16) { pointRow(points.count - 1, compact: true) }
                Button(action: onShowAll) {
                    GoFlyIconLabel(title: goFlyLocalizedFormat(goFlyString("imports.points.allCount"), points.count),
                                   icon: .routeList)
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("imports.points.showAll")
            } else {
                ForEach(points.indices, id: \.self) { index in
                    GoFlyListRow(minimumHeight: 46,
                                 separatorLeadingInset: index < points.count - 1 ? 16 : nil,
                                 separatorTrailingInset: 16) {
                        pointRow(index, compact: true)
                    }
                }
            }
        }
    }

    private func pointRow(_ index: Int, compact: Bool = false) -> some View {
        Button { onFocus(points[index]) } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .goFlyFont(GoFlyFont.footnote).monospacedDigit().lineLimit(1)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .frame(width: 40, alignment: .leading)
                Text(pointText(points[index]))
                    .goFlyFont(GoFlyFont.subheadline).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if index == 0 || index == points.count - 1 {
                    Text(goFlyString(index == 0 ? "route.origin" : "route.destination"))
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 46 : 52, alignment: .leading)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("imports.point.\(index)")
    }

    private func pointText(_ coordinate: GeoCoordinate) -> String {
        String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"),
               coordinate.latitude, coordinate.longitude)
    }
}

struct GoFlyGPXPointsView: View {
    let document: GPXDocument
    let title: String
    var onFocus: (GeoCoordinate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            GoFlySheetHeader(title: goFlyString("imports.points.title")) {
                Button { dismiss() } label: {
                    GoFlyIconLabel(title: goFlyString("common.back"), icon: .chevronLeft)
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(GoFlyTextColor.accent)
                .accessibilityLabel(goFlyString("common.back"))
                .accessibilityIdentifier("imports.points.back")
            } trailing: {
                EmptyView()
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title + " · " + goFlyLocalizedFormat(
                            goFlyString("imports.pointsFormat"),
                            document.pointCount.formatted(.number.locale(GoFlyPreferences.shared.locale))))
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(goFlyString("imports.points.readOnly"))
                            .goFlyFont(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityIdentifier("imports.points.readOnly")
                    }
                    GoFlyGPXPointList(points: document.segments.flatMap { $0 }, onFocus: { coordinate in
                        dismiss()
                        onFocus(coordinate)
                    })
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("imports.points.content")
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .goFlyPushedFullScreen()
    }
}
