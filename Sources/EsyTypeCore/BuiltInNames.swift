import Foundation

/// Common product names the speech engine splits or misspells, corrected when the switch is on. A fixed list,
/// kept apart from the user's dictionary (never edited, never exported). Names that are also everyday words
/// (Claude, Notion, Python, Excel, Gemini) are left out on purpose: add them to your dictionary if you want them.
public enum BuiltInNames {
    public static let names: [(name: String, heard: [String])] = [
        ("ChatGPT", ["chat gpt", "chatgpt", "chat g p t", "chat gbt", "chat g b t"]),
        ("OpenAI", ["openai", "open ai"]),
        ("PostgreSQL", ["postgresql", "postgres ql", "postgre sql", "postgres q l"]),
        ("Supabase", ["superbase", "supa base", "super base"]),
        ("Microsoft Copilot", ["microsoft co-pilot", "microsoft co pilot"]),
        ("GitHub", ["github", "git hub"]),
        ("GitLab", ["gitlab", "git lab"]),
        ("JavaScript", ["javascript", "java script"]),
        ("TypeScript", ["typescript", "type script"]),
        ("macOS", ["mac os", "macos"]),
        ("iPhone", ["iphone", "i phone"]),
        ("iPad", ["ipad", "i pad"]),
        ("YouTube", ["youtube", "you tube"]),
        ("LinkedIn", ["linkedin", "linked in"]),
        ("WhatsApp", ["whatsapp", "whats app", "what's app"]),
        ("PowerPoint", ["powerpoint", "power point"]),
        ("Wi-Fi", ["wifi", "wi fi"]),
        ("Gmail", ["g mail", "gmail"]),
        ("DeepSeek", ["deepseek", "deep seek"]),
        ("Midjourney", ["mid journey", "midjourney"]),
        ("Kubernetes", ["kuber netes", "kubernetes"]),
        ("PlayStation", ["playstation", "play station"]),
        ("Xcode", ["x code", "xcode"]),
        ("TikTok", ["tiktok", "tik tok", "tick tock"]),
        ("SharePoint", ["sharepoint", "share point"]),
        ("OneDrive", ["onedrive", "one drive"]),
        ("Hugging Face", ["huggingface", "hugging face"]),
        ("Anthropic", ["anthropic", "anthropik"]),
        ("EsyAI", ["esy ai", "easy ai"]),
    ]

    static let rules: [(key: String, replacement: String)] =
        names.flatMap { name in name.heard.map { (PhraseMatcher.key($0), name.name) } }
}
