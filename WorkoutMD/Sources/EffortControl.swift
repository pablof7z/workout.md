import SwiftUI

/// The "How hard was it?" prompt, opened by TAPPING `StepPageView`'s round done/skip thumb (a tap,
/// distinct from the thumb's horizontal slide-to-done/slide-to-skip gesture — see `DoneSkipThumb`'s
/// doc comment for how the two are disambiguated). Presented as a small sheet from
/// `StepPageView.SetGestureLayer`.
///
/// This replaces the old always-visible top-trailing effort dial: there's no separate committed vs.
/// expanded state to manage here, and no explicit "Set" confirm step either — the RPE 6–10 Easy→Max
/// scale (same labels/colors as `EffortScale` in `Models.swift`) is laid out as five tappable
/// swatches, and the moment one is tapped, `onSelect` fires immediately. The caller
/// (`SetGestureLayer`) is what actually records the RPE, marks the set `.done`, dismisses this sheet,
/// and auto-advances the pager — this view only reports which value was picked.
struct EffortPromptSheet: View {
    /// The RPE already committed for this set, if any — highlighted so re-opening the prompt shows
    /// where it currently stands.
    let current: Double?
    var onSelect: (Double) -> Void

    private let values: [Double] = [6, 7, 8, 9, 10]

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text("How hard was it?")
                    .font(.title3.weight(.bold))
                Text("Tap a value to log it and mark this set done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                ForEach(values, id: \.self) { rpe in
                    EffortSwatch(
                        rpe: rpe,
                        isCommitted: current.map { Int($0.rounded()) == Int(rpe) } ?? false
                    ) {
                        onSelect(rpe)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }
}

/// One tappable "6 / Easy" swatch in the effort prompt's scale — its fill uses the same calm→hot
/// `EffortScale.color(for:)` story the old drag-scale used, just as discrete stops instead of a
/// continuous gradient knob.
private struct EffortSwatch: View {
    let rpe: Double
    let isCommitted: Bool
    var onTap: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            onTap()
        } label: {
            VStack(spacing: 6) {
                Text("\(Int(rpe))")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(EffortScale.label(for: rpe))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .foregroundStyle(isCommitted ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EffortScale.color(for: rpe).opacity(isCommitted ? 0.95 : 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(EffortScale.color(for: rpe).opacity(isCommitted ? 0 : 0.4), lineWidth: 1.5)
        )
        .accessibilityLabel("RPE \(Int(rpe)), \(EffortScale.label(for: rpe))")
        .accessibilityAddTraits(isCommitted ? [.isSelected] : [])
    }
}
