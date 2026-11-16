import Foundation

struct SarvamModelOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
}

struct SarvamVoicePreferences: Codable, Equatable {
    var language = "en-IN"
    var voice = "shubh_enhi_ads"
    var pace = 1.0
    var temperature = 0.6
    var pitch = 0.0
    var loudness = 1.0
    var preprocessing = false
    var sampleRate = 22050
    var codec = "wav"
    static func defaults(_ model: String) -> Self {
        var value = Self()
        value.voice = model == "bulbul:v2" ? "anushka" : model == "bulbul:v3" ? "shubh" : model == "bulbul:v4-flash" ? "shubh_enhi_ads" : ""
        return value
    }
}

struct SarvamSpeechSettings: Codable, Equatable {
    var model = "bulbul:v4-flash"
    var profiles: [String: SarvamVoicePreferences] = [:]
    var selected: SarvamVoicePreferences { profiles[model] ?? .defaults(model) }
    var signature: String {
        let p = selected
        if !SarvamCatalog.models.contains(model) { return "sarvam|Default voice|\(model)|\(p.language)|provider-defaults" }
        func number(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
        var fields = ["sarvam",p.voice,model,p.language,number(p.pace),String(p.sampleRate),p.codec]
        fields += model == "bulbul:v2" ? [number(p.pitch),number(p.loudness),p.preprocessing ? "1" : "0"] : [number(p.temperature)]
        return fields.joined(separator: "|")
    }
}

struct LocalSummarySpeech: Codable, Equatable {
    var engine = "system"
    var systemVoice = ""
    var piperVoice = ""
    var rate = 1.0
    var pitch = 1.0
    var volume = 1.0
}

struct SarvamCatalog: Decodable {
    struct Voice: Decodable, Identifiable {
        let id: String
        let name: String
        let style: String
        let model: String
        let languages: [String]
        let demoUrl: String?
        var styleLabel: String {
            let normalized = style.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
            return ["ads":"Advertising", "ads formal":"Advertising — Formal", "ads informal":"Advertising — Informal", "edtech":"Education", "edtech bot":"Education assistant", "kyc":"Identity verification", "ecomm":"Shopping", "customer":"Customer support", "customer expressive":"Customer support — Expressive", "customer utility":"Customer support — Everyday", "customer warm":"Customer support — Warm", "latenight":"Late night", "latenight warm":"Late night — Warm", "news breaking":"Breaking news"][normalized] ?? normalized.capitalized
        }
        var label: String { styleLabel.isEmpty ? name : "\(name) — \(styleLabel)" }
    }
    let languages: [String: String]
    let voices: [Voice]
    static var models: [String] { shared.voices.reduce(into: []) { result, voice in if !result.contains(voice.model) { result.append(voice.model) } } }
    static func modelLabel(_ model: String) -> String {
        ["bulbul:v4-flash":"Bulbul v4 Flash", "bulbul:v3":"Bulbul v3", "bulbul:v2":"Bulbul v2"][model] ?? model.replacingOccurrences(of: ":", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }
    static let shared: SarvamCatalog = {
        let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/sarvam-voices.json")
        if let url, let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        return Self(languages: [:], voices: [])
    }()
}

extension StudioSettings {
    var usesCloudNarration: Bool { ["gemini", "sarvam", "elevenlabs"].contains(ttsMode) }
    var elevenlabsApiKey: String { KeychainStore.elevenlabs.read() ?? "" }
    var narrationService: OnlineService? { if ttsMode == "elevenlabs" { return .elevenlabs }; return ttsMode == "sarvam" ? .sarvam : ttsMode == "gemini" ? .gemini : nil }
    var sarvamApiKey: String { get { KeychainStore.sarvam.read() ?? "" } set { _ = KeychainStore.sarvam.write(newValue) } }
    var hasSarvamApiKey: Bool { !sarvamApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var initialSummarySpeech: LocalSummarySpeech {
        var profile = LocalSummarySpeech()
        profile.systemVoice = systemVoice
        profile.piperVoice = piperVoice
        profile.rate = systemSpeechRate; profile.pitch = systemSpeechPitch; profile.volume = systemSpeechVolume
        return profile
    }
    var resolvedSummarySettings: StudioSettings {
        guard usesCloudNarration else { return self }
        let local = summarySpeech ?? initialSummarySpeech
        var settings = self
        settings.ttsMode = local.engine == "piper" ? "piper" : "system"
        settings.systemVoice = local.systemVoice; settings.piperVoice = local.piperVoice
        settings.systemSpeechRate = local.rate; settings.systemSpeechPitch = local.pitch; settings.systemSpeechVolume = local.volume
        return settings
    }
}
