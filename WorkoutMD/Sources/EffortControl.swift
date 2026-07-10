import SwiftUI

/// An expressive, interactive effort input that replaces the old Easy/Moderate/Hard pills.
///
/// Collapsed, it's a small icon-only round glass button (a gauge/heart-rate glyph, no label — the
/// tint color already conveys severity once rated). Tapping it morphs — via a shared
/// `glassEffectID` inside a `GlassEffectContainer` — into an interactive glass scale: a calm→hot
/// gradient track with a draggable knob and a large live value that scales and recolors as you
/// drag. It maps to RPE 6–10 with detents at each integer, ticking a selection haptic at each
/// detent and a light impact on commit. Releasing records the value into the shared
/// `WorkoutSession`; tapping the committed state re-opens it to adjust.
struct EffortControl: View {
    /// The committed RPE for the current set (nil until the user rates it).
    let committed: Double?
    /// Lets the parent toolbar (see `ControlsView`) hide its sibling Skip/Finish button while this
    /// is expanded — the expanded scale needs the full row width, so the two can't coexist.
    @Binding var expanded: Bool
    var onCommit: (Double) -> Void

    @State private var value: Double = 8
    @State private var lastDetent: Int = 8
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            if expanded {
                expandedScale
                    .glassEffectID("effort", in: glass)
            } else {
                collapsed
                    .glassEffectID("effort", in: glass)
            }
        }
        .animation(.snappy(duration: 0.32), value: expanded)
    }

    // MARK: Collapsed

    private var collapsed: some View {
        Button {
            value = committed ?? 8
            lastDetent = Int(value.rounded())
            withAnimation(.snappy(duration: 0.32)) { expanded = true }
        } label: {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(committed == nil ? .white : .black)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .glassEffect(
            committed.map { .regular.tint(EffortScale.color(for: $0)).interactive() } ?? .regular.interactive(),
            in: .circle
        )
        .accessibilityLabel("Rate effort")
        .accessibilityValue(committed.map { "RPE \(Int($0.rounded())), \(EffortScale.label(for: $0))" } ?? "Not rated")
    }

    // MARK: Expanded scale

    private var expandedScale: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(EffortScale.color(for: value))
                    .contentTransition(.numericText(value: value))
                VStack(alignment: .leading, spacing: 0) {
                    Text(EffortScale.label(for: value))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("RPE")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button {
                    Haptics.impact(.light)
                    onCommit((value).rounded())
                    withAnimation(.snappy(duration: 0.32)) { expanded = false }
                } label: {
                    Text("Set")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                }
                .buttonStyle(.glassProminent)
                .tint(EffortScale.color(for: value))
            }

            track
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knob: CGFloat = 30
            let usable = max(1, width - knob)
            let fraction = (value - EffortScale.minRPE) / (EffortScale.maxRPE - EffortScale.minRPE)
            let x = knob / 2 + usable * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                EffortScale.color(for: 6),
                                EffortScale.color(for: 7),
                                EffortScale.color(for: 8),
                                EffortScale.color(for: 9),
                                EffortScale.color(for: 10)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(height: 12)
                    .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(EffortScale.color(for: value), lineWidth: 4))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .position(x: x, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(1, max(0, (g.location.x - knob / 2) / usable))
                        let newValue = EffortScale.minRPE + f * (EffortScale.maxRPE - EffortScale.minRPE)
                        value = newValue
                        let detent = Int(newValue.rounded())
                        if detent != lastDetent {
                            lastDetent = detent
                            Haptics.selection()
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.snappy) { value = value.rounded() }
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Effort scale")
        .accessibilityValue("RPE \(Int(value.rounded())), \(EffortScale.label(for: value))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(EffortScale.maxRPE, value.rounded() + 1)
            case .decrement: value = max(EffortScale.minRPE, value.rounded() - 1)
            default: break
            }
            lastDetent = Int(value.rounded())
            Haptics.selection()
        }
    }
}
