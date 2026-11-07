import Foundation

enum PromptDefaults {
    /// Upgrade exact former built-in fields while retaining independently edited fields.
    static func upgrading(_ saved: [String: Any], defaults: [String: Any]) -> [String: Any] {
        guard var prompts = saved["prompts"] as? [String: [String: String]],
              let current = defaults["prompts"] as? [String: [String: String]],
              let legacy = defaults["legacyPromptDefaults"] as? [String: [String: [String]]] else { return saved }
        for (stage, fields) in legacy {
            for (field, previous) in fields {
                if let value = prompts[stage]?[field], previous.contains(value),
                   let replacement = current[stage]?[field] {
                    prompts[stage]?[field] = replacement
                }
            }
        }
        var upgraded = saved
        upgraded["prompts"] = prompts
        return upgraded
    }
}
