// Copyright Sierra

import UIKit

/// Renders the voice disclosure's inline Markdown. Only http, https, mailto, and tel links with a
/// target are kept, with a lowercase scheme; any other link renders as its plain label.
enum DisclosureMarkdown {
    private static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    static func attributedText(_ markdown: String, font: UIFont) -> AttributedString {
        var text = (try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(markdown)
        for run in text.runs {
            if let link = run.link {
                text[run.range].link = allowedLink(link)
            }
            let intent = run.inlinePresentationIntent ?? []
            // UITextView ignores presentation intents, so apply them as font traits.
            let baseFont = intent.contains(.code) ? UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
            var traits = baseFont.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            text[run.range].uiKit.font = baseFont.fontDescriptor.withSymbolicTraits(traits)
                .map { UIFont(descriptor: $0, size: font.pointSize) } ?? baseFont
        }
        return text
    }

    /// Returns the link with a lowercase scheme, so `onLinkClick` sees the same URL as on Android.
    private static func allowedLink(_ url: URL) -> URL? {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            allowedLinkSchemes.contains(scheme),
            // A link needs a target, so `https://` and `mailto:` alone are not links.
            url.absoluteString.dropFirst(scheme.count + 1).contains(where: { $0 != "/" })
        else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }
}
