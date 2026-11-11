"""Project language choices must describe saved content, not the output catalog."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_contextual_menus import MAC, WIN, declaration

CASES = [
 ('en','summary','saved',{'summary':'Hello'},True),
 ('fr','summary','saved',{'summary':'  \n '},False),
 ('de','transcript','saved',{'transcript':[]},False),
 ('hi','transcript','saved',{'transcript':[{'text':'Hello'}]},True),
 ('auto','descriptions','saved',{'cues':[{'text':'Description'}]},True),
 ('mr','descriptions','saved',{'importedADTranscript':{'segments':[{'text':'Imported'}]}},True),
 ('es','adAudio','saved',{'importedAudioDescription':{'path':'audio/one.wav'}},True),
 ('it','adAudio','saved',{'importedAudioDescription':{'path':''}},False),
 ('ja','summary','draft',{'summary':'Waiting for review'},False),
 ('ko','summary','discarded',{'summary':'Removed'},False),
 ('','summary','saved',{'summary':'No language'},False),
 ('zz-custom','summary','saved',{'summary':'Older project language'},True),
 ('hi','summary','saved',{'summary':'Second saved version'},True),
]

class LibraryLanguageFilters(unittest.TestCase):
    def test_mac_production_saved_content_and_choices(self):
        src=(MAC/'VidiStudio/LanguageResults.swift').read_text()
        output=declaration(src,'struct OutputLanguage:')
        saved=declaration(src,'struct SavedLanguageResult:')
        codes=declaration(src,'var projectFilterLanguageCodes:')
        match=declaration(src,'func matchesLanguage(')
        stubs='''import SwiftUI
struct Row: Codable {var text:String}
struct ImportedAD: Codable {var segments:[Row]}
struct Audio: Codable {var path:String}
struct SavedSourceAsset: Codable {}
struct SavedLanguagePayload: Codable {
 var transcript:[Row]?;var summary:String?;var cues:[Row]?;var importedADTranscript:ImportedAD?;var importedAudioDescription:Audio?
}
'''
        harness=stubs+output+'\n'+saved+'\nstruct StudioProject { var savedLanguageResults:[SavedLanguageResult]\n'+codes+'\n'+match+'\n}\n@main struct Main { static func main() {\nvar rows=[SavedLanguageResult]()\n'
        for language,kind,state,payload,expected in CASES:
            data=json.dumps(payload,ensure_ascii=False)
            harness+='do { let payload=try! JSONDecoder().decode(SavedLanguagePayload.self,from:Data('+json.dumps(data)+'.utf8)); let row=SavedLanguageResult(id:UUID().uuidString,kind:'+json.dumps(kind)+',language:'+json.dumps(language)+',version:1,createdAt:0,updatedAt:0,origin:"test",state:'+json.dumps(state)+',payload:payload);let project=StudioProject(savedLanguageResults:[row]);precondition(project.matchesLanguage('+json.dumps(language)+') == '+str(expected).lower()+');precondition(project.matchesLanguage("all")); rows.append(row) }\n'
        expected=sorted(set(case[0] for case in CASES if case[4]))
        harness+='let project=StudioProject(savedLanguageResults:rows);let options=OutputLanguage.projectFilterOptions([project,project]);precondition(Set(options.map(\\.id)) == Set('+json.dumps(expected)+'));precondition(options.count == '+str(len(expected))+');precondition(OutputLanguage.projectFilterOptions([]).isEmpty);precondition(!project.matchesLanguage("ar"));precondition(StudioProject(savedLanguageResults:[]).matchesLanguage("all"));print("PASS: real Swift content policy, deduplication, empty library and unknown saved languages")\n} }'
        self.compile_swift(harness)

    def compile_swift(self,harness):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_windows_production_saved_content_and_choices(self):
        source=(WIN/'Vidi Studio Windows/Models/StudioProject.cs').read_text()
        codes=source[source.index('    [JsonIgnore] public IReadOnlyList<string> ProjectFilterLanguageCodes'):source.index('    public event PropertyChangedEventHandler?',source.index('ProjectFilterLanguageCodes'))]
        harness='''using System;using System.Linq;using System.Collections.Generic;using System.Text.Json;using System.Text.Json.Serialization;
using Vidi_Studio_Windows.Models;
namespace Vidi_Studio_Windows.Models {public class StudioProject {public List<LanguageResult> SavedResults {get;set;}=new();
'''+codes+'\n} }\nclass MainProgram {static void Main() {var rows=new List<LanguageResult>();\n'
        for language,kind,state,payload,expected in CASES:
            harness+='{var row=new LanguageResult {Language='+json.dumps(language)+',Kind='+json.dumps(kind)+',State='+json.dumps(state)+',Payload=JsonDocument.Parse('+json.dumps(json.dumps(payload))+').RootElement};var project=new StudioProject {SavedResults=new(){row}};if(project.MatchesLanguage('+json.dumps(language)+') != '+str(expected).lower()+')throw new Exception("Wrong saved-content match");rows.Add(row);}\n'
        expected=sorted(set(case[0] for case in CASES if case[4]))
        harness+='var all=new StudioProject {SavedResults=rows};var options=OutputLanguage.ProjectFilterOptions(new[]{all,all});if(!options.Select(o=>o.Id).OrderBy(id=>id,StringComparer.Ordinal).SequenceEqual(new[]{'+','.join(json.dumps(c) for c in expected)+'}))throw new Exception("Wrong options");if(OutputLanguage.ProjectFilterOptions(Array.Empty<StudioProject>()).Count!=0 || !new StudioProject().MatchesLanguage("all") || all.MatchesLanguage("ar"))throw new Exception("Empty/unknown match");Console.WriteLine("PASS: real C# content policy, deduplication, empty library and unknown saved languages");} }'
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Program.cs').write_text(harness)
            (path/'LanguageResult.cs').write_text((WIN/'Vidi Studio Windows/Models/LanguageResult.cs').read_text())
            (path/'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
            result=subprocess.run(['dotnet','run','--project',str(path/'Check.csproj')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_choices_and_matches_share_unfiltered_content_source(self):
        page=(MAC/'VidiStudio/ProjectBrowserPage.swift').read_text()
        menu=(MAC/'VidiStudio/KeyboardShortcuts.swift').read_text()
        self.assertIn('OutputLanguage.projectFilterOptions(projects)',page)
        self.assertIn('options: languageOptions',page)
        self.assertIn('}, languageOptions: languageOptions',page)
        self.assertIn('ForEach(allProjects.languageOptions)',menu)
        self.assertIn('!options.contains(where: { $0.id == languageFilter })',page)
        model=(WIN/'Vidi Studio Windows/ViewModels/StudioViewModel.cs').read_text()
        self.assertLess(model.index('OutputLanguage.ProjectFilterOptions(loaded)'),model.index('var desired = loaded.Where'))
        self.assertIn('LanguageFilter = "all";',model)
        windows=(WIN/'Vidi Studio Windows/MainWindow.Menus.cs').read_text()
        self.assertIn('Concat(Model.ProjectFilterLanguages)',windows)
        self.assertIn('string.Join("|", Model.ProjectFilterLanguages.Select',windows)
        ui=(WIN/'Vidi Studio Windows/MainWindow.LanguageResults.cs').read_text()
        self.assertIn('updatingLanguageFilters',ui)
        self.assertIn('!current.SequenceEqual(options)',ui)
        self.assertNotIn('Concat(OutputLanguage.Options).ToList();\n        GalleryLanguageFilter',ui)
