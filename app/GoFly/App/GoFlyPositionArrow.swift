import GoFlyCore
import MapKit
import SwiftUI

/// A position has an arrow silhouette, never the place pin's round head.
/// Both layers share one path, so the contrast keyline cannot drift from the fill.
final class GoFlyPositionArrowView: MKAnnotationView {
    private let drawing = CALayer()
    private let glyph = CALayer()
    private var source = PositionSource.gps
    private var freshness = PositionFreshness.waiting
    private var targetRotation: CGFloat?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        drawing.frame = bounds
        layer.addSublayer(drawing)
        glyph.frame = bounds.insetBy(dx: 5, dy: 5)
        glyph.contentsScale = traitCollection.displayScale
        glyph.contentsGravity = .resizeAspect
        drawing.addSublayer(glyph)
        isAccessibilityElement = true
        accessibilityIdentifier = "map.positionMarker"
        canShowCallout = false
        // The current position stays above every route node; a route usually
        // starts at it, and its start ring would otherwise hide the arrow.
        zPriority = .max
        selectedZPriority = .max
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: GoFlyPositionArrowView, _: UITraitCollection) in view.applyColors()
        }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ marker: PositionMarker, bearingDegrees: Double?, cameraHeadingDegrees: Double) {
        applyAppearance(source: marker.source, freshness: marker.freshness,
                        bearingDegrees: bearingDegrees, cameraHeadingDegrees: cameraHeadingDegrees)
        let key: String
        switch (marker.source, marker.freshness) {
        case (.gps, .fresh): key = "map.realLocation"
        case (.gps, .waiting): key = "map.realLocationWaiting"
        case (.simulation, .fresh): key = "map.simulatedLocation"
        case (.simulation, .waiting): key = "map.simulatedLocationWaiting"
        }
        accessibilityLabel = goFlyString(key)
        accessibilityValue = marker.coordinate.displayText
    }

#if DEBUG && targetEnvironment(simulator)
    /// Screenshot fixture only: B8 is designed with a confirmed GPS glyph, but
    /// simulator fixtures do not create real Core Location fixes.
    func applyFixtureRealLocationStyle(bearingDegrees: Double?, cameraHeadingDegrees: Double) {
        applyAppearance(source: .gps, freshness: .fresh,
                        bearingDegrees: bearingDegrees, cameraHeadingDegrees: cameraHeadingDegrees)
        accessibilityLabel = goFlyString("map.realLocation")
    }
#endif

    /// The preview exercises these same production layers without inventing a GPS fix or ACK.
    func applyAppearance(source: PositionSource, freshness: PositionFreshness,
                         bearingDegrees: Double?, cameraHeadingDegrees: Double) {
        let changed = self.source != source || self.freshness != freshness
        self.source = source
        self.freshness = freshness
        alpha = freshness == .waiting ? 0.5 : 1
        let radians = CGFloat(bearingDegrees.map { ($0 - cameraHeadingDegrees) * .pi / 180 } ?? 0)
        rotate(to: radians)
        if changed { applyColors() }
    }

    private func rotate(to radians: CGFloat) {
        if UIAccessibility.isReduceMotionEnabled {
            targetRotation = radians
            drawing.removeAnimation(forKey: "arrow.rotation")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            drawing.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
            CATransaction.commit()
            return
        }
        guard let previousTarget = targetRotation else {
            targetRotation = radians
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            drawing.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
            CATransaction.commit()
            return
        }

        guard abs(radians - previousTarget) > 0.005 else { return }
        let presentationRotation = (drawing.presentation()?.value(forKeyPath: "transform.rotation.z") as? NSNumber)
            .map { CGFloat(truncating: $0) } ?? previousTarget
        var delta = radians - presentationRotation
        delta.formTruncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        guard abs(delta) > 0.005 else { return }

        targetRotation = radians
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = presentationRotation
        animation.toValue = presentationRotation + delta
        animation.duration = 0.24
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        drawing.add(animation, forKey: "arrow.rotation")
        applyColors()
        CATransaction.commit()
    }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let asset: GoFlyIconAsset
        switch (source, freshness, dark) {
        case (.gps, _, _): asset = .mapRealLocation
        case (.simulation, .fresh, false): asset = .mapSimulationLight
        case (.simulation, .fresh, true): asset = .mapSimulationDark
        case (.simulation, .waiting, false): asset = .mapSimulationWaitingLight
        case (.simulation, .waiting, true): asset = .mapSimulationWaitingDark
        }
        glyph.contents = GoFlyIcon.uiImage(asset)?.cgImage
    }
}
