import GoFlyCore
import SwiftUI

enum GoFlyBackgroundDuration {
    /// Short form for the F6 row value (Figma "1 hr").
    @MainActor static func summary(seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60
        let h = goFlyString("settings.background.duration.hr")
        let m = goFlyString("settings.background.duration.min")
        switch (hours, minutes) {
        case (0, _): return "\(minutes) \(m)"
        case (_, 0): return "\(hours) \(h)"
        default: return "\(hours) \(h) \(minutes) \(m)"
        }
    }
}

/// Time input for how long a movement keeps running after the app moves to
/// the background (Figma F6.a, 336 pt sheet): header, 130 pt wheel 16 pt
/// below it, 40 pt above the button.
struct GoFlyBackgroundDurationSheet: View {
    let seconds: Int
    var onChange: (Int) -> Void
    var onDismiss: () -> Void

    @State private var hours: Int
    @State private var minutes: Int
    private let original: Int

    init(seconds: Int, onChange: @escaping (Int) -> Void, onDismiss: @escaping () -> Void) {
        self.seconds = seconds
        self.original = seconds
        self.onChange = onChange
        self.onDismiss = onDismiss
        _hours = State(initialValue: seconds / 3600)
        _minutes = State(initialValue: seconds % 3600 / 60)
    }

    private var total: Int { hours * 3600 + minutes * 60 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                GoFlyNavActionButton(title: goFlyString("common.cancel"), identifier: "settings.background.duration.cancel") {
                    cancel()
                }
                Spacer()
                GoFlyNavActionButton(title: goFlyString("common.done"), isProminent: true, identifier: "settings.background.duration.done") {
                    onDismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            timePickerWheel
                .padding(.top, 16)
                .padding(.horizontal, 16)

            Button(action: onDismiss) {
                Text(goFlyString("common.doneSetting"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .frame(height: 56)
            .accessibilityIdentifier("settings.background.duration.confirm")
            .padding(.top, 24)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hours) { _, _ in commit() }
        .onChange(of: minutes) { _, _ in commit() }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
        .presentationBackgroundInteraction(.enabled)
    }

    /// Figma `TimePicker / Wheel` (`238:9472`): 361 × 128 pt card with 3 rows of numbers and center selection band.
    private var timePickerWheel: some View {
        ZStack {
            HStack(spacing: 0) {
                wheel(selection: $hours, range: 0...24, format: { "\($0)" },
                      unit: goFlyString("settings.background.duration.wheelUnit.hours"),
                      label: "settings.background.duration.hours",
                      identifier: "settings.background.duration.hours")
                Text(":")
                    .goFlyFont(GoFlyFont.title)
                    .foregroundStyle(GoFlyTextColor.disabled)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                wheel(selection: $minutes, range: 0...59, format: { String(format: "%02d", $0) },
                      unit: goFlyString("settings.background.duration.wheelUnit.minutes"),
                      label: "settings.background.duration.minutes",
                      identifier: "settings.background.duration.minutes")
            }
        }
        .frame(height: 128)
        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
        )
    }

    /// A real wheel: dragging scrolls continuously through the values and the
    /// selection settles on the row under the band.
    private func wheel(selection: Binding<Int>, range: ClosedRange<Int>, format: @escaping (Int) -> String,
                       unit: String, label: String, identifier: String) -> some View {
        HStack(spacing: 4) {
            Picker(goFlyString(label), selection: selection) {
                ForEach(Array(range), id: \.self) { value in
                    Text(format(value))
                        .goFlyFont(GoFlyFont.title)
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(identifier)
            Text(unit)
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.primary)
                .padding(.trailing, 8)
        }
    }

    /// Keeps the total inside 1 minute…24 h 59 min.
    private func commit() {
        let clamped = Int(BackgroundRunDuration.clamp(TimeInterval(total)))
        if clamped != total {
            hours = clamped / 3600
            minutes = clamped % 3600 / 60
        }
        onChange(clamped)
    }

    private func cancel() {
        onChange(original)
        onDismiss()
    }
}
