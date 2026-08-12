import SwiftUI
import WebKit

/// Ported unchanged from RockingLife's `ProviderLogoView.swift`. Renders a model maker's logo (SVG,
/// fetched from models.dev) over an initials fallback so a row/detail is never a blank tile while the
/// image loads (or if the provider has no logo at all).
struct ProviderLogoView: View {
    var providerID: String
    var providerName: String
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemFill))

            Text(initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            SVGLogoView(url: logoURL)
                .padding(6)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private var logoURL: URL {
        URL(string: "https://models.dev/logos/\(providerID).svg")!
    }

    private var initials: String {
        let pieces = providerName
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." })
            .prefix(2)
        let text = pieces.compactMap(\.first).map(String.init).joined()
        return text.isEmpty ? String(providerID.prefix(2)).uppercased() : text.uppercased()
    }
}

/// A transparent, non-scrolling `WKWebView` that renders a single `<img>` — the simplest way to get
/// SVG rendering on iOS without pulling in a third-party SVG library.
private struct SVGLogoView: UIViewRepresentable {
    var url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        let html = """
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: transparent; }
              body { display: flex; align-items: center; justify-content: center; overflow: hidden; }
              img { max-width: 100%; max-height: 100%; object-fit: contain; }
            </style>
          </head>
          <body><img src="\(url.absoluteString)" /></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var currentURL: URL?
    }
}
