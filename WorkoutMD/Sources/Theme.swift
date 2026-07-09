import SwiftUI

/// Maps each movement/moment to a full-bleed background color story so the pager feels alive as
/// the workout moves through chest, back, shoulders, and rest.
extension MoodKey {
    var gradientColors: [Color] {
        switch self {
        case .bench:
            return [Color(red: 0.28, green: 0.06, blue: 0.09), Color(red: 0.05, green: 0.01, blue: 0.03)]
        case .inclinePress:
            return [Color(red: 0.24, green: 0.09, blue: 0.32), Color(red: 0.04, green: 0.02, blue: 0.09)]
        case .row:
            return [Color(red: 0.03, green: 0.21, blue: 0.23), Color(red: 0.01, green: 0.05, blue: 0.07)]
        case .facePull:
            return [Color(red: 0.30, green: 0.07, blue: 0.20), Color(red: 0.05, green: 0.01, blue: 0.06)]
        case .cableFly:
            return [Color(red: 0.05, green: 0.12, blue: 0.32), Color(red: 0.01, green: 0.03, blue: 0.09)]
        case .plank:
            return [Color(red: 0.05, green: 0.22, blue: 0.15), Color(red: 0.01, green: 0.05, blue: 0.04)]
        case .rest:
            return [Color(red: 0.08, green: 0.09, blue: 0.14), Color(red: 0.01, green: 0.01, blue: 0.03)]
        }
    }

    var glowColor: Color {
        switch self {
        case .bench: return Color(red: 0.95, green: 0.30, blue: 0.28)
        case .inclinePress: return Color(red: 0.72, green: 0.40, blue: 0.95)
        case .row: return Color(red: 0.20, green: 0.85, blue: 0.75)
        case .facePull: return Color(red: 0.95, green: 0.38, blue: 0.65)
        case .cableFly: return Color(red: 0.38, green: 0.58, blue: 0.95)
        case .plank: return Color(red: 0.38, green: 0.90, blue: 0.55)
        case .rest: return Color(red: 0.45, green: 0.50, blue: 0.68)
        }
    }
}

/// Full-bleed, edge-to-edge background used behind every pager page — never a card, always the
/// whole screen. It fills its containing page frame OPAQUELY (opaque gradient over solid black)
/// and deliberately does NOT call `.ignoresSafeArea()`: inside the paging ScrollView each page is
/// already sized to the full screen, and letting a page's background ignore the safe area would
/// let it bleed into the adjacent page and ghost through the translucent glass controls. The base
/// black layer guarantees zero transparency even if a sub-pixel seam ever shows.
struct BackgroundView: View {
    let moodKey: MoodKey

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(colors: moodKey.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [moodKey.glowColor.opacity(0.30), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 460
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
