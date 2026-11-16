import Foundation
import AVFoundation
import Observation

struct ElevenLabsSpeechSettings: Codable, Equatable {
    var model = "", voice = "", voiceName = "", language = "auto", format = "mp3_44100_128"
    var originalVoice: String? = nil
    var controls: [String] = []
    var stability = 0.5, stabilityMode = 0.5, similarity = 0.75, style = 0.0, speed = 1.0, cloneStrength = 0.0
    var speakerBoost = true
    var signature: String {
        var fields = ["elevenlabs", voice, model, language, format]
        for key in controls.sorted() {
            if key == "speakerBoost" { fields.append(key + "=" + (speakerBoost ? "1" : "0")); continue }
            let values = ["stability":stability,"stabilityMode":stabilityMode,"similarity":similarity,"style":style,"speed":speed,"cloneStrength":cloneStrength]
            if let value = values[key] { fields.append(key + "=" + String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value)) }
        }
        return fields.joined(separator:"|")
    }
}
struct ElevenLabsOption: Codable, Identifiable { let id: String; let name: String }
struct ElevenLabsModel: Codable, Identifiable {
    let id: String; let name: String; let controls: [String]; let languages: [ElevenLabsOption]
}
struct ElevenLabsVariant: Codable {
    let language: String; let model: String; let accent: String; let locale: String; let preview: String
    var label: String { [Locale.current.localizedString(forIdentifier: locale.isEmpty ? language : locale) ?? language, accent.capitalized].filter { !$0.isEmpty }.joined(separator:" · ") }
}
struct ElevenLabsVoice: Codable, Identifiable {
    let id: String; let name: String; let description: String; let owner: String; let category: String; let original: String
    let language: String; let accent: String; let gender: String; let age: String; let style: String; let useCase: String; let preview: String
    let variants: [ElevenLabsVariant]; let tuning: [String:String]
    var detail: String { [Locale.current.localizedString(forLanguageCode:language) ?? language, accent, gender, style, useCase].filter { !$0.isEmpty }.map { $0.replacingOccurrences(of:"_",with:" ").capitalized }.joined(separator:" · ") }
    var hasDemo: Bool { !preview.isEmpty || variants.contains { !$0.preview.isEmpty } }
}
struct ElevenLabsPlan: Codable {
    let tier: String?; let status: String?; let character_count: Int?; let character_limit: Int?
    let next_character_count_reset_unix: Double?; let voice_slots_used: Int?; let voice_limit: Int?; let billing_period: String?
    var rows: [(String,String)] {
        var result: [(String,String)] = []
        if let tier { result.append(("Plan",tier.replacingOccurrences(of:"_",with:" ").capitalized)) }
        if let status { result.append(("Status",status.replacingOccurrences(of:"_",with:" ").capitalized)) }
        if let used=character_count, let limit=character_limit {
            result.append(("Usage this period", "\(used.formatted()) / \(limit.formatted())"))
            result.append(("Remaining allowance", max(0,limit-used).formatted()))
        }
        if let date=next_character_count_reset_unix { result.append(("Allowance resets",Date(timeIntervalSince1970:date).formatted(date:.abbreviated,time:.omitted))) }
        if let used=voice_slots_used,let limit=voice_limit { result.append(("Saved voices","\(used) / \(limit)")) }
        if let billing_period { result.append(("Billing period",["monthly_period":"Monthly","annual_period":"Annual","3_month_period":"Every 3 months","6_month_period":"Every 6 months"][billing_period] ?? billing_period.replacingOccurrences(of:"_",with:" ").capitalized)) }
        return result
    }
}
struct ElevenLabsResponse: Decodable {
    var keyStatus: String?; var message: String?; var error: String?; var kind: String?
    var plan: ElevenLabsPlan?; var planCached: Bool?; var planMessage: String?
    var models: [ElevenLabsModel]?; var modelsCached: Bool?; var formats: [ElevenLabsOption]?
    var voices: [ElevenLabsVoice]?; var voicesCached: Bool?; var hasMore: Bool?; var cursor: String?; var page: Int?
    var addedVoice: ElevenLabsVoice?; var demoPath: String?; var filterOptions: [String:[ElevenLabsOption]]?
}
enum ElevenLabsRequest {
    static func run(_ action: String, key: String, payload: [String:Any] = [:]) async throws -> ElevenLabsResponse {
        let body = String(decoding:try JSONSerialization.data(withJSONObject:payload, options:.sortedKeys),as:UTF8.self)
        return try await Task.detached(priority:.userInitiated) {
            let process=Process(), pipe=Pipe()
            process.executableURL=Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine")
            process.arguments=["elevenlabs-settings","--elevenlabs-action",action,"--elevenlabs-request",body]
            var env=ProcessInfo.processInfo.environment
            for name in ["VIDISTUDIO_API_KEY","VIDISTUDIO_SARVAM_API_KEY","VIDISTUDIO_ELEVENLABS_API_KEY"] { env.removeValue(forKey:name) }
            env["VIDISTUDIO_ELEVENLABS_API_KEY"]=key;process.environment=env
            process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
            try process.run()
            let watchdog=DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline:.now()+150,execute:watchdog)
            defer { watchdog.cancel() }
            let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
            for line in data.split(separator:10).reversed() {
                if let event=try? JSONSerialization.jsonObject(with:Data(line)) as? [String:Any],let result=event["elevenlabs"],let encoded=try? JSONSerialization.data(withJSONObject:result) {
                    return try JSONDecoder().decode(ElevenLabsResponse.self,from:encoded)
                }
            }
            throw NSError(domain:"ElevenLabs",code:1,userInfo:[NSLocalizedDescriptionKey:"ElevenLabs could not complete the request."])
        }.value
    }
}
@MainActor @Observable final class ElevenLabsBrowser: NSObject, AVAudioPlayerDelegate {
    var models: [ElevenLabsModel] = []
    var voices: [ElevenLabsVoice] = []
    var formats: [ElevenLabsOption] = []
    var plan: ElevenLabsPlan?
    var planMessage=""
    var message=""
    var keyMessage="No API key"
    var status="unverified"
    var loading=false
    var checking=false
    var hasMore=false
    var cursor=""
    var page=0
    var playing: String?
    var preparing: String?
    var source="account"
    var search=""
    var sort="name"
    var modelSort="name"
    var accents: [ElevenLabsOption] = []
    var filterOptions: [String:[ElevenLabsOption]] = [:]
    var filters: [String:String] = [:]
    private var revision=UUID()
    private var queryRevision=UUID()
    private var audioRevision=UUID()
    private var owner=UUID()
    private var audio: AVAudioPlayer?
    private var observedKey=""
    private var updated: Date?
    func stop() { audioRevision=UUID();audio?.stop();audio=nil;playing=nil;preparing=nil;VoiceSampleSession.shared.end(owner) }
    func changedKey(_ key: String) {
        let old=observedKey;observedKey=key;revision=UUID();queryRevision=UUID();stop()
        models=[];voices=[];accents=[];filterOptions=[:];plan=nil;planMessage="";message="";status="unverified";keyMessage=key.isEmpty ? "No API key" : "API key saved — not yet checked";checking=false;loading=false;updated=nil
        if !old.isEmpty && old != key { Task { _ = try? await ElevenLabsRequest.run("forget",key:old) } }
    }
    func refresh(key: String) async {
        if observedKey != key { changedKey(key) }
        guard !key.isEmpty,!checking else { return }
        let request=revision;checking=true;status="checking";keyMessage="Checking API key…"
        defer { if request==revision { checking=false } }
        do {
            let result=try await ElevenLabsRequest.run("check",key:key)
            guard request==revision else { return }
            status=result.keyStatus ?? "unavailable";keyMessage=result.error ?? result.message ?? "Key check unavailable"
            plan=result.plan;planMessage=result.planMessage ?? "";updated=Date()
            if result.kind == "invalid" { models=[];voices=[];return }
            let catalog=try await ElevenLabsRequest.run("models",key:key)
            guard request==revision else { return }
            if let rows=catalog.models { models=rows };formats=catalog.formats ?? [];accents=catalog.filterOptions?["accent"] ?? []
            message=catalog.error ?? (catalog.modelsCached == true ? "Using saved models" : "")
        } catch { guard request==revision else { return };status="unavailable";keyMessage="Could not check the key. Check your connection." }
    }
    func load(key: String, language: String, more: Bool = false) async {
        let request=UUID();queryRevision=request
        var payload: [String:Any]=["source":source,"search":search,"sort":sort,"language":language]
        for (key,value) in filters where !value.isEmpty && value != "all" { payload[key]=value }
        if more { payload["cursor"]=cursor;payload["page"]=page+1 }
        let credentialRevision=revision;loading=true
        do {
            let result=try await ElevenLabsRequest.run("voices",key:key,payload:payload)
            guard request==queryRevision,credentialRevision==revision else { return }
            if let rows=result.voices { voices=more ? voices+rows.filter { row in !voices.contains { $0.id==row.id } } : rows }
            filterOptions=result.filterOptions ?? [:]
            hasMore=result.hasMore ?? false;cursor=result.cursor ?? "";page=result.page ?? 0
            message=result.error ?? (result.voicesCached == true ? "Using saved voices" : "")
        } catch { if request==queryRevision { message="Could not load voices. Try again." } }
        if request==queryRevision { loading=false }
    }
    func add(_ voice: ElevenLabsVoice,key: String) async -> ElevenLabsVoice? {
        let request=revision
        do {
            let result=try await ElevenLabsRequest.run("add",key:key,payload:["voice":voice.id])
            guard request==revision else { return nil };message=result.error ?? ""
            if result.addedVoice != nil { await refresh(key:key) };return result.addedVoice
        } catch { if request==revision { message="Could not add this voice. Refresh My Voices before trying again." };return nil }
    }
    func play(_ voice: ElevenLabsVoice,key: String,model: String,language: String,variant: ElevenLabsVariant? = nil) {
        if playing==voice.id || preparing==voice.id { stop();return }
        guard VoiceSampleSession.shared.begin(owner) else { return }
        let request=UUID();audioRevision=request;preparing=voice.id
        Task {
            do {
                let result=try await ElevenLabsRequest.run("demo",key:key,payload:["voice":voice.id,"model":model,"language":variant?.language ?? language,"locale":variant?.locale ?? ""])
                guard audioRevision==request else { return }
                guard let path=result.demoPath else { throw NSError(domain:"ElevenLabs",code:2,userInfo:[NSLocalizedDescriptionKey:result.error ?? "Sample unavailable."]) }
                audio=try AVAudioPlayer(contentsOf:URL(fileURLWithPath:path));audio?.delegate=self
                preparing=nil;playing=voice.id
                if audio?.play() != true { stop();message="Could not play this demo." }
            } catch { if audioRevision==request { stop();message=error.localizedDescription } }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,successfully flag: Bool) { Task { @MainActor [weak self] in if self?.audio === player { self?.stop() } } }
}
