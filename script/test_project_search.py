"""Execute production Swift/C# search projections against the same multilingual fixture."""
from pathlib import Path
import json, subprocess, tempfile, sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tests.test_contextual_menus import declaration
MAC=Path(__file__).resolve().parents[1]; WIN=MAC.parent/'Vidi-Studio-Windows'
def row(text): return dict(id='same-id',text=text,start=1,end=2)
def result(id,kind,payload,state='saved',language='en'):
 return dict(id=id,kind=kind,language=language,state=state,version=1,createdAt=1,updatedAt=1,payload=payload)
fixture=dict(id='search-fixture',selectedLanguage='en',updatedAt=1,activeResultIDs={'transcript':'selected','descriptions':'des','summary':'sum'},languageResults=[
 result('old','transcript',dict(transcript=[row('Beacon older dialogue.')])),
 result('selected','transcript',dict(transcript=[row('Unrelated selected dialogue.')])),
 result('draft','transcript',dict(transcript=[row('Beacon draft dialogue.')]),'draft'),
 result('other-language','transcript',dict(transcript=[row('Beacon excluded language.')]),language='hi'),
 result('des','descriptions',dict(cues=[row('Beacon description.')],importedADTranscript=dict(mode='narration',segments=[row('Beacon description.')]))),
 result('des-draft','descriptions',dict(cues=[row('Beacon draft description.')]),'draft'),
 result('combined','descriptions',dict(importedADTranscript=dict(mode='combined',segments=[row('Beacon combined import.')]))),
 result('sum','summary',dict(summary='# Overview\n\nBeacon arrives. This sentence stays hidden.')),
 result('sum-draft','summary',dict(summary='First hidden. Beacon draft sentence!'),'draft'),
 result('sum-long','summary',dict(summary='Beacon '+('long '*150)+'.')),
 result('empty-cues','descriptions',dict(cues=[],importedADTranscript=dict(mode='narration',segments=[row('Imported fallback content.')]))),
])
swift_stubs=r'''
struct Segment: Codable {var id:String;var text:String;var start:Double;var end:Double}
struct ImportedADTranscript: Codable {var mode:String;var segments:[Segment]}
struct SavedLanguagePayload: Codable {var transcript:[Segment]?;var cues:[Segment]?;var summary:String?;var importedADTranscript:ImportedADTranscript?}
struct SavedLanguageResult: Codable, Identifiable {var id:String;var kind:String;var language:String;var state:String;var version:Int;var createdAt:Double;var updatedAt:Double;var payload:SavedLanguagePayload;var title:String {"Version 1"}}
struct StudioProject: Codable {var id:String;var selectedLanguage:String;var updatedAt:Double;var activeResultIDs:[String:String];var languageResults:[SavedLanguageResult];var languageCode:String {selectedLanguage};var savedLanguageResults:[SavedLanguageResult] {languageResults};func activeLanguageResultID(_ kind:String)->String {activeResultIDs[kind] ?? ""}}
'''
swift_check=r'''
var project=try JSONDecoder().decode(StudioProject.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let before=try JSONEncoder().encode(project)
let search=ProjectSearchState();search.update(project);search.text="beacon"
let expected=["transcript":2,"summary":3,"descriptions":2,"ad-transcript":5]
for (section,count) in expected {precondition((search.groups[section] ?? []).reduce(0){$0+$1.hits.count}==count,section)}
let summary=search.groups["summary"]!.flatMap(\.hits)
precondition(summary.contains{$0.text=="Beacon arrives."} && !summary.contains{$0.text.contains("stays hidden")})
precondition(summary.contains{$0.text.count>700},"Complete long sentences must not use TTS chunks")
let ids=search.groups.values.flatMap{$0}.flatMap(\.hits).map(\.id);precondition(Set(ids).count==ids.count)
search.selectedHitID=search.groups["transcript"]!.first!.hits.first!.id;precondition(search.selectedHit != nil)
for (prefix,section) in [(" Tr : ","transcript"),("SuM:","summary"),("DES:","descriptions"),("adt :", "ad-transcript")] {
 search.text=prefix+"Beacon";precondition(search.query.section==section && search.groups.keys.sorted()==[section])
 search.text=prefix;precondition(search.groups.isEmpty && !search.query.applies(to:section))
}
precondition(ProjectSearchQuery("café").matches("CAFE\u{301}"))
for (prefix, section) in [(" Tr ", "transcript"), ("sUm", "summary"), ("DES", "descriptions"), ("AdT", "ad-transcript")] {
 for value in [prefix, prefix.trimmingCharacters(in: .whitespaces)+":"] {
  search.text=value;precondition(search.query.section==section && search.query.term.isEmpty && search.groups.isEmpty)
 }
}
for word in ["transfer", "summary", "describe", "adventure", "sum total", "tr beacon"] {precondition(ProjectSearchQuery(word).section==nil)}
let unicodeText="🎬 CAFE\u{301} and café."
precondition(ProjectSearchQuery("café").matchingRanges(in:unicodeText).map {NSRange($0,in:unicodeText)} == [NSRange(location:3,length:5),NSRange(location:13,length:4)])
precondition(ProjectSearchQuery("Tr:beacon").matchingRanges(in:"Beacon beacon BEACON").count==3)
precondition(ProjectSearchQuery("").matchingRanges(in:"Beacon").isEmpty)
precondition(SearchResultStatus.editor(query:ProjectSearchQuery("beacon"),section:"transcript",count:2)=="2 search results in Transcript.")
precondition(SearchResultStatus.editor(query:ProjectSearchQuery("beacon"),section:"summary",count:1)=="1 search result in Summary.")
precondition(SearchResultStatus.editor(query:ProjectSearchQuery("beacon"),section:"descriptions",count:0)=="No search results in Descriptions.")
precondition(SearchResultStatus.editor(query:ProjectSearchQuery(""),section:"ad-transcript",count:0)=="Search cleared. All AD Transcript content shown.")
precondition(SearchResultStatus.gallery(query:"beacon",count:0)=="No projects found.")
precondition(SearchResultStatus.gallery(query:"",count:1)=="Search cleared. 1 project shown.")
let plain="Beacon beacon BEACON"
let highlighted=ProjectSearchHighlight.text(plain,query:ProjectSearchQuery("Tr:beacon"),enabled:true,color:"#102040")
precondition(String(highlighted.characters)==plain && highlighted.runs.filter{$0.backgroundColor != nil}.count==3)
precondition(highlighted.runs.filter{$0.backgroundColor != nil}.allSatisfy{$0.foregroundColor == Color.white})
let disabled=ProjectSearchHighlight.text(plain,query:ProjectSearchQuery("beacon"),enabled:false,color:"#102040")
precondition(String(disabled.characters)==plain && disabled.runs.allSatisfy{$0.backgroundColor==nil})
let yellow=ProjectSearchHighlight.text("Beacon",query:ProjectSearchQuery("beacon"),enabled:true,color:ProjectSearchHighlight.defaultColor)
precondition(yellow.runs.first?.foregroundColor==Color.black)
var pickedColor=Color.yellow
private let colorCoordinator=SearchHighlightColorWell.Coordinator(color:Binding(get:{pickedColor},set:{pickedColor=$0}))
let nativeWell=NSColorWell()
nativeWell.color=NSColor(srgbRed:16/255,green:32/255,blue:64/255,alpha:1)
colorCoordinator.changed(nativeWell)
precondition(SummaryHighlightColor.hex(from:pickedColor)=="#102040","Native color changes must reach persisted hex preferences")
var highlightSettings=HighlightSettingsFixture()
highlightSettings.restoreHighlightDefaults()
precondition(highlightSettings.summarySentenceHighlightEnabled && highlightSettings.summaryWordHighlightEnabled && highlightSettings.searchHighlightEnabled)
precondition(highlightSettings.summarySentenceHighlight=="#0A84FF" && highlightSettings.summaryWordHighlight=="#FFD60A" && highlightSettings.searchHighlightColor=="#FFD60A")
precondition(highlightSettings.captionFontSize==39,"Highlight reset must preserve caption preferences")
precondition(ProjectSearchQuery("foo: beacon").section==nil && ProjectSearchQuery("foo: beacon").term=="foo: beacon")
search.text="beacon";project.selectedLanguage="hi";search.update(project);precondition(search.groups["transcript"]!.flatMap(\.hits).count==1)
project.selectedLanguage="en";project.updatedAt=2;search.update(project);precondition(search.groups["transcript"]!.flatMap(\.hits).count==2)
search.text="no-match";precondition(search.groups.isEmpty && search.selectedHitID==nil)
search.text="";precondition(search.groups.isEmpty)
project.id="different";search.text="beacon";search.update(project);precondition(search.text.isEmpty)
print("PASS: Swift styled highlights, native color binding and search prefixes, all saved/draft versions, language isolation, sentence snippets, imports, identities, empty/clear and cache revisions")
'''
cs_stubs=r'''
using System;using System.Collections.Generic;using System.Linq;using System.Text.Json;using Vidi_Studio_Windows.Models;
var project=JsonSerializer.Deserialize<StudioProject>(System.IO.File.ReadAllText(args[0]),Json.Options)!;
var before=JsonSerializer.Serialize(project,Json.Options);var search=new ProjectTextSearch();Check(search.Update(project));Check(!search.Update(project));
foreach(var pair in new[]{("transcript",2),("summary",3),("descriptions",2),("ad-transcript",5)}) Check(search.Search(ProjectSearchQuery.Parse("beacon"),pair.Item1).Sum(g=>g.Hits.Count)==pair.Item2,pair.Item1);
var summary=search.Search(ProjectSearchQuery.Parse("beacon"),"summary").SelectMany(g=>g.Hits).ToList();
Check(summary.Any(h=>h.Text=="Beacon arrives.") && !summary.Any(h=>h.Text.Contains("stays hidden")));Check(summary.Any(h=>h.Text.Length>700));
var all=new[]{"transcript","summary","descriptions","ad-transcript"}.SelectMany(s=>search.Search(ProjectSearchQuery.Parse("beacon"),s)).SelectMany(g=>g.Hits).ToList();Check(all.Select(h=>h.Id).Distinct().Count()==all.Count);
foreach(var pair in new[]{(" Tr : ","transcript"),("SuM:","summary"),("DES:","descriptions"),("adt :","ad-transcript")}) {var q=ProjectSearchQuery.Parse(pair.Item1+"Beacon");Check(q.Section==pair.Item2 && q.Applies(pair.Item2));Check(!ProjectSearchQuery.Parse(pair.Item1).Applies(pair.Item2));}
Check(ProjectSearchQuery.Parse("café").Matches("CAFE\u0301"));
foreach(var pair in new[]{(" Tr ","transcript"),("sUm","summary"),("DES","descriptions"),("AdT","ad-transcript")})
 foreach(var value in new[]{pair.Item1,pair.Item1.Trim()+":"}) {var q=ProjectSearchQuery.Parse(value);Check(q.Section==pair.Item2 && q.Term=="" && !q.Applies(pair.Item2));}
foreach(var word in new[]{"transfer","summary","describe","adventure","sum total","tr beacon"}) Check(ProjectSearchQuery.Parse(word).Section==null);
var unicodeRanges=ProjectSearchQuery.Parse("café").MatchingRanges("🎬 CAFE\u0301 and café.");
Check(unicodeRanges.SequenceEqual(new[]{(3,5),(13,4)}),"Original UTF-16 highlight offsets");
Check(ProjectSearchQuery.Parse("Tr:beacon").MatchingRanges("Beacon beacon BEACON").Count==3);
Check(ProjectSearchQuery.Parse("").MatchingRanges("Beacon").Count==0);Check(ProjectSearchQuery.Parse("foo: beacon").Section==null);
Check(SearchResultStatus.Editor(ProjectSearchQuery.Parse("beacon"),"transcript",2)=="2 search results in Transcript.");
Check(SearchResultStatus.Editor(ProjectSearchQuery.Parse("beacon"),"summary",1)=="1 search result in Summary.");
Check(SearchResultStatus.Editor(ProjectSearchQuery.Parse("beacon"),"descriptions",0)=="No search results in Descriptions.");
Check(SearchResultStatus.Editor(ProjectSearchQuery.Parse(""),"ad-transcript",0)=="Search cleared. All AD Transcript content shown.");
Check(SearchResultStatus.Gallery("beacon",0)=="No projects found.");Check(SearchResultStatus.Gallery("",1)=="Search cleared. 1 project shown.");
Check(JsonSerializer.Serialize(project,Json.Options)==before,"Searching changed the project");
project.SelectedLanguage="hi";search.Update(project);Check(search.Search(ProjectSearchQuery.Parse("beacon"),"transcript").Sum(g=>g.Hits.Count)==1);
Check(search.Search(ProjectSearchQuery.Parse(""),"summary").Count==0 && search.Search(ProjectSearchQuery.Parse("absent"),"summary").Count==0);
Console.WriteLine("PASS: C# Unicode highlight offsets and search prefixes, all saved/draft versions, language isolation, sentence snippets, imports, identities and cache revisions");
static void Check(bool value,string message="Search regression") {if(!value)throw new Exception(message);}
namespace Vidi_Studio_Windows.Models {
 public static class Json {public static JsonSerializerOptions Options=new(){PropertyNameCaseInsensitive=true};}
 public sealed class Segment {public string Id{get;set;}="";public string Text{get;set;}="";public double Start{get;set;}public double End{get;set;}}
 public sealed class ImportedADTranscript {public string Mode{get;set;}="";public List<Segment> Segments{get;set;}=new();}
 public sealed class LanguageResult {public string Id{get;set;}="";public string Kind{get;set;}="";public string Language{get;set;}="";public string State{get;set;}="";public double UpdatedAt{get;set;}public JsonElement Payload{get;set;}public string Title=>"Version 1";}
 public sealed class StudioProject {public string Id{get;set;}="";public string SelectedLanguage{get;set;}="";public Dictionary<string,JsonElement>? Extra{get;set;}public List<LanguageResult> LanguageResults{get;set;}=new();public List<LanguageResult> SavedResults=>LanguageResults;public Dictionary<string,string> ActiveResultIDs{get;set;}=new();public string ActiveResultID(string kind)=>ActiveResultIDs.GetValueOrDefault(kind,"");}
}
'''
with tempfile.TemporaryDirectory(prefix='vidi-project-search-') as temporary:
 p=Path(temporary);(p/'fixture.json').write_text(json.dumps(fixture,ensure_ascii=False))
 source=(MAC/'VidiStudio/SummaryReadback.swift').read_text()
 parser=declaration(source,'struct SummarySentence:')+'\n'+declaration(source,'enum SummarySpeechParser')
 well=declaration((MAC/'VidiStudio/SettingsView.swift').read_text(),'private struct SearchHighlightColorWell')
 reset=declaration((MAC/'VidiStudio/StudioModel.swift').read_text(),'mutating func restoreHighlightDefaults()')
 well+='\nstruct HighlightSettingsFixture {var summarySentenceHighlightEnabled=false;var summaryWordHighlightEnabled=false;var searchHighlightEnabled=false;var summarySentenceHighlight="#FF0000";var summaryWordHighlight="#00FF00";var searchHighlightColor="#0000FF";var captionFontSize=39;'+reset+'}\n'
 style=well+'\n'+declaration((MAC/'VidiStudio/ProjectSearchResultsView.swift').read_text(),'enum ProjectSearchHighlight')+'\n'+declaration(source,'enum SummaryHighlightColor')
 (p/'main.swift').write_text('import SwiftUI\nimport AppKit\n'+(MAC/'VidiStudio/ProjectTextSearch.swift').read_text()+swift_stubs+parser+'\n'+style+swift_check)
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(p/'modules'),str(p/'main.swift'),'-o',str(p/'swift-check')],check=True)
 subprocess.run([str(p/'swift-check'),str(p/'fixture.json')],check=True)
 (p/'Program.cs').write_text(cs_stubs)
 (p/'ProjectTextSearch.cs').write_text((WIN/'Vidi Studio Windows/Models/ProjectTextSearch.cs').read_text())
 (p/'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
 subprocess.run(['dotnet','run','--project',str(p/'Check.csproj'),'--',str(p/'fixture.json')],check=True)
