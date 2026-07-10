import SwiftUI

/// A calm, full-bleed, three-screen first-run sequence: track -> coach -> own your data. Shown
/// once (gated by `AppSettings.hasOnboarded`, set from `onFinished`) before the athlete ever sees
/// Today. Reuses the same `BackgroundView` mood-gradient language as the rest of the app rather
/// than introducing a separate onboarding visual style, per the no-cards, full-bleed doctrine.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            moodKey: .bench,
            glyph: "list.bullet.rectangle.portrait",
            title: "Track every set",
            body: "Log weight, reps, and effort as you go — a clean record of every session, one set at a time."
        ),
        OnboardingPage(
            moodKey: .cableFly,
            glyph: "quote.bubble",
            title: "A coach that adapts",
            body: "Tell it how a set felt. It adjusts the next one in real time — and can repair a whole session on the fly."
        ),
        OnboardingPage(
            moodKey: .plank,
            glyph: "lock.doc",
            title: "Own your data",
            body: "Every workout is plain Markdown, synced to your own GitHub repo or iCloud — never locked away."
        )
    ]

    var body: some View {
        ZStack {
            BackgroundView(moodKey: pages[page].moodKey)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: page)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.bottom, 20)

                footerButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index == page ? 0.9 : 0.25))
                    .frame(width: index == page ? 18 : 6, height: 6)
                    .animation(.snappy, value: page)
            }
        }
    }

    private var footerButton: some View {
        Button {
            Haptics.impact(.light)
            if page < pages.count - 1 {
                withAnimation(.easeInOut) { page += 1 }
            } else {
                onFinished()
            }
        } label: {
            Text(page < pages.count - 1 ? "Continue" : "Get started")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.glassProminent)
        .tint(.indigo)
        .accessibilityHint(page < pages.count - 1 ? "Shows the next introduction screen" : "Adds a coach provider key in Settings and starts using the app")
    }
}

private struct OnboardingPage {
    let moodKey: MoodKey
    let glyph: String
    let title: String
    let body: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            Image(systemName: page.glyph)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: .circle)

            Text(page.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            Text(page.body)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
