import SwiftUI
import AppKit

struct ElevenLabsVoiceSettingsView: View {
    @Bindable var studio: StudioModel
    @State private var browser=ElevenLabsBrowser()
    @State private var key=""
    @State private var storageError: String?
    @State private var deleteKey=false
    @State private var addVoice=false
    @State private var pendingVoice: ElevenLabsVoice?
    @State private var keyTask: Task<Void,Never>?
    @FocusState private var focus: String?
    @Environment(\.openURL) private var openURL
    private var preferences: ElevenLabsSpeechSettings { studio.settings.elevenlabsSpeech ?? ElevenLabsSpeechSettings() }
    private var selectedModel: ElevenLabsModel? { browser.models.first { $0.id==preferences.model } }
    private var query: String { [browser.source,browser.search,browser.sort,preferences.language,key,browser.filters.sorted { $0.key<$1.key }.map { $0.key+"="+$0.value }.joined(separator:"|")].joined(separator:"|") }
    private func setting<T>(_ path: WritableKeyPath<ElevenLabsSpeechSettings,T>) -> Binding<T> {
        Binding(get:{ preferences[keyPath:path] },set:{ value in browser.stop();var p=preferences;p[keyPath:path]=value;studio.settings.elevenlabsSpeech=p })
    }
    private func selectModel(_ id: String) {
        var p=preferences;p.model=id;p.controls=browser.models.first { $0.id==id }?.controls.filter { $0 != "cloneStrength" } ?? []
        if p.language != "auto", !(browser.models.first { $0.id==id }?.languages.contains { $0.id==p.language } ?? false) { p.language="auto" }
        studio.settings.elevenlabsSpeech=p;browser.stop()
    }
    private func selectVoice(_ voice: ElevenLabsVoice) {
        var p=preferences;p.voice=voice.id;p.voiceName=voice.name;p.originalVoice=voice.original
        p.controls=selectedModel?.controls.filter { $0 != "cloneStrength" || (voice.category=="professional" && voice.tuning[p.model]=="fine_tuned") } ?? []
        studio.settings.elevenlabsSpeech=p;browser.stop()
    }
    private func refresh() async {
        await browser.refresh(key:key)
        if preferences.model.isEmpty,let model=browser.models.first { selectModel(model.id) }
        await browser.load(key:key,language:preferences.language)
    }
    private func action(_ title: String,_ id: String, enabled: Bool = true,run: @escaping () -> Void) -> some View {
        Button(title) { if enabled { run() } }.disabled(!enabled).accessibilityIdentifier(id)
            .contextMenu { Button(title) { if enabled { run() } }.disabled(!enabled).accessibilityIdentifier(id) }
    }
    private func searchField(_ title: String,_ id: String,text: Binding<String>) -> some View {
        HStack {
            Image(systemName:"magnifyingglass").accessibilityHidden(true)
            TextField(title,text:text).focused($focus,equals:id).accessibilityIdentifier(id)
            if !text.wrappedValue.isEmpty { action("Clear",id+"-clear") { text.wrappedValue="" } }
        }.padding(6).background(.quaternary,in:RoundedRectangle(cornerRadius:6))
        .contextMenu {
            Button("Focus " + title) { focus=id }.accessibilityIdentifier(id+"-focus")
            Button("Clear " + title) { text.wrappedValue="" }.accessibilityIdentifier(id+"-clear")
        }
    }
    private func filterChoice(_ title: String,_ field: String,_ all: String) -> some View {
        var options=browser.filterOptions[field] ?? []
        if field=="accent" { for option in browser.accents where !options.contains(where:{ $0.id==option.id }) { options.append(option) } }
        let selected=browser.filters[field] ?? "all"
        if selected != "all",!options.contains(where:{ $0.id==selected }) { options.append(ElevenLabsOption(id:selected,name:selected.replacingOccurrences(of:"_",with:" ").capitalized)) }
        return SpeechChoice(title:title,id:"elevenlabs-filter-"+field,value:Binding(get:{ browser.filters[field] ?? "all" },set:{ browser.filters[field]=$0 }),options:[("all",all)]+options.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { ($0.id,$0.name) })
    }
    var body: some View {
        Section {
            HStack(spacing:8) {
                SecureField("ElevenLabs API key",text:$key).focused($focus,equals:"elevenlabs-key").accessibilityIdentifier("elevenlabs-api-key")
                    .contextMenu { Button("Edit ElevenLabs API Key") { focus="elevenlabs-key" }.accessibilityIdentifier("elevenlabs-key-edit") }
                Image(systemName:browser.checking ? "clock" : browser.status=="verified" ? "checkmark.circle.fill" : browser.status=="invalid" ? "xmark.circle.fill" : "key")
                    .foregroundStyle(browser.status=="verified" ? Color.green : browser.status=="invalid" ? .red : .secondary)
                    .help(browser.keyMessage).accessibilityLabel(browser.keyMessage).accessibilityIdentifier("elevenlabs-key-status")
                Button(role:.destructive) { deleteKey=true } label: { Image(systemName:"trash").foregroundStyle(.red) }
                    .buttonStyle(.borderless).disabled(key.isEmpty).help("Delete ElevenLabs API key").accessibilityLabel("Delete ElevenLabs API key").accessibilityIdentifier("elevenlabs-key-delete-icon")
                    .contextMenu { Button("Delete ElevenLabs API Key…",role:.destructive) { deleteKey=true }.disabled(key.isEmpty).accessibilityIdentifier("elevenlabs-key-delete") }
            }
            HStack {
                action(browser.checking ? "Checking API Key…" : "Check API Key","elevenlabs-key-check",enabled:!key.isEmpty && !browser.checking) { keyTask?.cancel();Task { await refresh() } }
                action("Open ElevenLabs API Keys","elevenlabs-key-dashboard") { openURL(URL(string:"https://elevenlabs.io/app/settings/api-keys")!) }
            }
            if let storageError { Text(storageError).foregroundStyle(.red) }
            if browser.status == "invalid" || browser.status == "unavailable" { Text(browser.keyMessage).foregroundStyle(.secondary) }
        } header: { Text("ElevenLabs Voices").accessibilityHeading(.h2) }
        if !key.isEmpty {
            Section {
                if let plan=browser.plan {
                    ForEach(plan.rows,id:\.0) { row in LabeledContent(row.0,value:row.1).accessibilityElement(children:.ignore).accessibilityLabel(row.0+": "+row.1) }
                } else { Text(browser.checking ? "Loading account plan…" : "Plan details unavailable") }
                if !browser.planMessage.isEmpty { Text(browser.planMessage).foregroundStyle(.secondary) }
            } header: { Text("Account Plan").accessibilityHeading(.h2) }
        }
        Section {
            SpeechChoice(title:"Sort models",id:"elevenlabs-model-sort",value:$browser.modelSort,options:[("name","Model name (A–Z)"),("descending","Model name (Z–A)")])
            SpeechChoice(title:"Model",id:"elevenlabs-model",value:Binding(get:{ preferences.model },set:selectModel),options:modelOptions)
            action("Refresh Models and Voices","elevenlabs-refresh",enabled:!key.isEmpty && !browser.checking) { Task { await refresh() } }
            SpeechChoice(title:"Narration language",id:"elevenlabs-language",value:setting(\.language),options:[("auto","Automatic")]+(selectedModel?.languages.map { ($0.id,$0.name) } ?? []))
            SpeechChoice(title:"Voice source",id:"elevenlabs-source",value:Binding(get:{ browser.source },set:{ browser.source=$0;browser.sort=$0=="library" ? "trending" : "name";browser.filters=[:] }),options:[("account","My Voices"),("library","Voice Library")])
            searchField("Search voices","elevenlabs-voice-search",text:$browser.search)
            SpeechChoice(title:"Sort voices",id:"elevenlabs-voice-sort",value:$browser.sort,options:browser.source=="library" ? [("trending","Trending"),("created_date","Newest"),("usage_character_count_1y","Most used"),("cloned_by_count","Most saved")] : [("name","Voice name (A–Z)"),("descending","Voice name (Z–A)"),("newest","Newest")])
            SpeechChoice(title:"Voice type",id:"elevenlabs-category",value:Binding(get:{ browser.filters["category"] ?? "all" },set:{ browser.filters["category"]=$0 }),options:[("all","All types")]+(browser.source=="library" ? [("professional","Professional"),("high_quality","Studio quality")] : [("premade","Default"),("cloned","Cloned"),("generated","Designed"),("professional","Professional")]))
            SpeechChoice(title:"Gender",id:"elevenlabs-gender",value:Binding(get:{ browser.filters["gender"] ?? "all" },set:{ browser.filters["gender"]=$0 }),options:[("all","All genders"),("female","Female"),("male","Male"),("other","Other")])
            SpeechChoice(title:"Age",id:"elevenlabs-age",value:Binding(get:{ browser.filters["age"] ?? "all" },set:{ browser.filters["age"]=$0 }),options:[("all","All ages"),("young","Young"),("middle_aged","Middle-aged"),("old","Older")])
            filterChoice("Accent","accent","All accents");filterChoice("Use case","useCase","All use cases")
            if browser.source=="library" { filterChoice("Style","style","All styles") }
            Text(preferences.voice.isEmpty ? "No voice selected" : "Selected: " + preferences.voiceName).font(.callout)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(browser.voices) { voice in voiceRow(voice) }
                    if browser.voices.isEmpty && !browser.loading { Text("No matching voices").foregroundStyle(.secondary) }
                }.padding(4)
            }.frame(minHeight:120,maxHeight:360).accessibilityIdentifier("elevenlabs-voices")
            if browser.loading { ProgressView().controlSize(.small).accessibilityLabel("Loading ElevenLabs voices") }
            HStack {
                action("Load More Voices","elevenlabs-more",enabled:browser.hasMore && !browser.loading) { Task { await browser.load(key:key,language:preferences.language,more:true) } }
                action("Reset Voice Filters","elevenlabs-filters-reset") { browser.search="";browser.filters=[:];browser.sort=browser.source=="library" ? "trending" : "name" }
            }
            if !browser.message.isEmpty { Text(browser.message).foregroundStyle(.secondary) }
        } header: { Text("Models and Voices").accessibilityHeading(.h2) }
        Section {
            adjustments
            SpeechChoice(title:"Audio quality",id:"elevenlabs-format",value:setting(\.format),options:browser.formats.map { ($0.id,$0.name) })
            action("Restore Voice Defaults","elevenlabs-controls-reset") {
                var p=ElevenLabsSpeechSettings();p.model=preferences.model;p.voice=preferences.voice;p.voiceName=preferences.voiceName;p.language=preferences.language;p.controls=preferences.controls;studio.settings.elevenlabsSpeech=p
            }
        } header: { Text("Voice Controls").accessibilityHeading(.h2) }
        .task { key=studio.settings.elevenlabsApiKey;browser.changedKey(key);await refresh() }
        .task(id:query) {
            do { try await Task.sleep(for:.milliseconds(350));guard !Task.isCancelled,!key.isEmpty,!browser.models.isEmpty else { return };await browser.load(key:key,language:preferences.language) } catch { }
        }
        .onChange(of:key) { _,value in
            guard value != studio.settings.elevenlabsApiKey else { return }
            keyTask?.cancel()
            if KeychainStore.elevenlabs.write(value.trimmingCharacters(in:.whitespacesAndNewlines)) {
                browser.changedKey(value.trimmingCharacters(in:.whitespacesAndNewlines));storageError=nil;studio.settings.elevenlabsKeyStatus="unverified";studio.settings.elevenlabsCredentialRevision += 1
                keyTask=Task { do { try await Task.sleep(for:.milliseconds(700));guard !Task.isCancelled else { return };await refresh() } catch { } }
            } else { storageError="Could not save the ElevenLabs API key to Keychain." }
        }
        .onChange(of:browser.status) { _,status in
            studio.settings.elevenlabsKeyStatus=status
            NSAccessibility.post(element:NSApp as Any,notification:.announcementRequested,userInfo:[.announcement:browser.keyMessage,.priority:NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .onChange(of:studio.busy) { _,busy in if !busy,!key.isEmpty { Task { await refresh() } } }
        .onDisappear { keyTask?.cancel();browser.stop() }
        .alert("Delete ElevenLabs API Key?",isPresented:$deleteKey) {
            Button("Delete API Key",role:.destructive) { key="" };Button("Cancel",role:.cancel) { }
        }
        .alert("Add Voice to ElevenLabs?",isPresented:$addVoice) {
            Button("Add & Select") { if let voice=pendingVoice { Task { if let added=await browser.add(voice,key:key) { selectVoice(added) } } } }
            Button("Cancel",role:.cancel) { pendingVoice=nil }
        } message: { Text(pendingVoice?.name ?? "") }
    }
    private var modelOptions: [(String,String)] {
        let rows=browser.models.sorted { browser.modelSort=="descending" ? $0.name.localizedStandardCompare($1.name) == .orderedDescending : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var result=rows.map { ($0.id,$0.name) }
        if !preferences.model.isEmpty,!result.contains(where:{ $0.0==preferences.model }) { result.append((preferences.model,browser.models.first { $0.id==preferences.model }?.name ?? "Selected model unavailable")) }
        return result
    }
    @ViewBuilder private var adjustments: some View {
        ForEach(preferences.controls,id:\.self) { control in
            switch control {
            case "stabilityMode": SpeechChoice(title:"Stability",id:"elevenlabs-stability-mode",value:Binding(get:{ String(preferences.stabilityMode) },set:{ setting(\.stabilityMode).wrappedValue=Double($0) ?? 0.5 }),options:[("0.0","Creative"),("0.5","Natural"),("1.0","Robust")])
            case "stability": SpeechAdjustment(title:"Stability",id:"elevenlabs-stability",value:setting(\.stability),range:0...1,initial:0.5,percentage:true)
            case "similarity": SpeechAdjustment(title:"Similarity",id:"elevenlabs-similarity",value:setting(\.similarity),range:0...1,initial:0.75,percentage:true)
            case "style": SpeechAdjustment(title:"Style emphasis",id:"elevenlabs-style",value:setting(\.style),range:0...1,initial:0,percentage:true)
            case "speed": SpeechAdjustment(title:"Speaking speed",id:"elevenlabs-speed",value:setting(\.speed),range:0.7...1.2,initial:1)
            case "cloneStrength": SpeechAdjustment(title:"Clone strength",id:"elevenlabs-clone-strength",value:setting(\.cloneStrength),range:0...1,initial:0,percentage:true)
            case "speakerBoost": Toggle("Speaker boost",isOn:setting(\.speakerBoost)).accessibilityIdentifier("elevenlabs-speaker-boost").contextMenu { Toggle("Speaker boost",isOn:setting(\.speakerBoost)).accessibilityIdentifier("elevenlabs-speaker-boost") }
            default: EmptyView()
            }
        }
    }
    private func visibleVariants(_ voice: ElevenLabsVoice) -> [ElevenLabsVariant] {
        var seen=Set<String>()
        return voice.variants.filter { $0.model==preferences.model && seen.insert($0.language+"|"+$0.locale+"|"+$0.accent).inserted }
    }
    private func choose(_ voice: ElevenLabsVoice) {
        if browser.source=="library" { pendingVoice=voice;addVoice=true } else { selectVoice(voice) }
    }
    private func demoButton(_ voice: ElevenLabsVoice,variant: ElevenLabsVariant? = nil) -> some View {
        let active=browser.playing==voice.id || browser.preparing==voice.id
        let label=(active ? "Stop demo of " : "Play demo of ")+voice.name+(variant.map { ", "+$0.label } ?? "")
        let enabled=(variant.map { !$0.preview.isEmpty } ?? voice.hasDemo) && (active || !VoiceSampleSession.shared.busy)
        return Button { browser.play(voice,key:key,model:preferences.model,language:preferences.language,variant:variant) } label: { Image(systemName:active ? "stop.circle" : "play.circle") }
            .disabled(!enabled).help(label).accessibilityLabel(label)
            .accessibilityIdentifier((variant == nil ? "elevenlabs-demo-" : "elevenlabs-demo-variant-")+voice.id+(variant?.locale ?? ""))
            .contextMenu {
                Button("Play Demo") { browser.play(voice,key:key,model:preferences.model,language:preferences.language,variant:variant) }.disabled(active || !enabled)
                Button("Stop Demo") { browser.stop() }.disabled(!active)
            }
    }
    private func voiceRow(_ voice: ElevenLabsVoice) -> some View {
        let selected=preferences.voice==voice.id || (preferences.originalVoice != nil && preferences.originalVoice==voice.original)
        return VStack(alignment:.leading,spacing:4) {
            Text(voice.name).fontWeight(.semibold).accessibilityAddTraits(.isHeader).accessibilityHeading(.h3)
            HStack {
                Button { choose(voice) } label: {
                    HStack { Image(systemName:selected ? "checkmark.circle.fill" : "circle");Text(voice.detail).font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.plain).help((browser.source=="library" ? "Add & select " : "Select ")+voice.name)
                    .accessibilityLabel((browser.source=="library" ? "Add & select " : "Select ")+voice.name+", "+voice.detail)
                    .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("elevenlabs-select-"+voice.id)
                    .contextMenu {
                        Toggle("Select "+voice.name,isOn:Binding(get:{ selected },set:{ if $0 { choose(voice) } }))
                    }
                Spacer()
                if browser.preparing==voice.id { ProgressView().controlSize(.small).accessibilityLabel("Preparing demo of "+voice.name) }
                demoButton(voice)
            }
            if !voice.hasDemo { Text("Sample unavailable").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(visibleVariants(voice).enumerated()),id:\.offset) { _,variant in
                HStack { Text(variant.label).font(.caption).foregroundStyle(.secondary);Spacer();demoButton(voice,variant:variant) }.padding(.leading,24)
            }
            Divider()
        }.accessibilityElement(children:.contain)
    }
}
