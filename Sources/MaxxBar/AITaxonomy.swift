import Foundation

/// MaxxBar's canonical vocabulary for AI tools, surfaces, sites, and broad use cases.
enum AITaxonomy {
    static func tool(appName: String, url: String?) -> (tool: String?, surface: String?) {
        if let url, let components = URLComponents(string: url), let host = components.host?.lowercased() {
            let path = components.path.lowercased()
            if host == "chatgpt.com", path.hasPrefix("/codex") {
                return ("Codex", "Codex web")
            }
            if host == "codex.openai.com" || host.hasSuffix(".codex.openai.com") {
                return ("Codex", "Codex web")
            }
            if host == "chatgpt.com" || host == "chat.openai.com" || host.hasSuffix(".chatgpt.com") {
                return ("ChatGPT", "ChatGPT web")
            }
            if host == "claude.ai" || host.hasSuffix(".claude.ai") {
                return ("Claude", "Claude web")
            }
            if host == "perplexity.ai" || host.hasSuffix(".perplexity.ai") {
                return ("Perplexity", "Perplexity web")
            }
            if host == "gemini.google.com" {
                return ("Gemini", "Gemini web")
            }
            if host == "copilot.microsoft.com" {
                return ("Copilot", "Copilot web")
            }
        }

        let lowerApp = appName.lowercased()
        if lowerApp.contains("codex") { return ("Codex", "Codex client") }
        if lowerApp.contains("chatgpt") { return ("ChatGPT", "ChatGPT client") }
        if lowerApp.contains("claude") { return ("Claude", "Claude client") }
        if lowerApp.contains("cursor") { return ("Cursor", "Cursor client") }
        if lowerApp.contains("windsurf") { return ("Windsurf", "Windsurf client") }
        if lowerApp.contains("github copilot") { return ("GitHub Copilot", "GitHub Copilot client") }
        return (nil, nil)
    }

    static func siteLabel(_ url: String) -> String? {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else { return nil }
        if host == "chatgpt.com", components.path.lowercased().hasPrefix("/codex") {
            return "Codex"
        }

        let known = [
            "mail.google.com": "Gmail", "calendar.google.com": "Calendar",
            "docs.google.com": "Google Docs", "sheets.google.com": "Google Sheets",
            "slides.google.com": "Google Slides", "github.com": "GitHub",
            "linear.app": "Linear", "notion.so": "Notion", "figma.com": "Figma",
            "claude.ai": "Claude", "chatgpt.com": "ChatGPT", "chat.openai.com": "ChatGPT",
            "codex.openai.com": "Codex", "perplexity.ai": "Perplexity",
            "gemini.google.com": "Gemini", "copilot.microsoft.com": "Copilot"
        ]
        if let label = known[host] { return label }
        let pieces = host.split(separator: ".")
        return pieces.count >= 2 ? pieces.suffix(2).joined(separator: ".") : host
    }

    static func useCase(before: String?, surface: String?, after: String?) -> String {
        let text = [before, surface, after].compactMap { $0?.lowercased() }.joined(separator: " ")
        if text.contains("xcode") || text.contains("terminal") || text.contains("github") || text.contains("cursor") || text.contains("codex") {
            return "Coding"
        }
        if text.contains("gmail") || text.contains("mail") || text.contains("slack") || text.contains("messages") || text.contains("calendar") {
            return "Email / comms"
        }
        if text.contains("docs") || text.contains("slides") || text.contains("sheets") || text.contains("markdown") || text.contains("pdf") {
            return "Docs / writing"
        }
        if text.contains("perplexity") || text.contains("chrome") || text.contains("safari") || text.contains("reddit") || text.contains("gemini") {
            return "Research"
        }
        if text.contains("linear") || text.contains("jira") || text.contains("notion") {
            return "Planning"
        }
        return surface == nil ? "Non-AI" : "Unknown"
    }
}
