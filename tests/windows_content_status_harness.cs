using System.Text.Json;
namespace Vidi_Studio_Windows.Models;
public sealed record Segment(string Text);
public sealed record AudioStatus(bool Complete, string Title, string AccessibleName);
public sealed class StudioProject {
 public List<Segment> Transcript = new(); public List<Segment> Cues = new(); public string Summary=""; public string SelectedLanguage="en";
 public List<LanguageResult> SavedResults = new();
 public StudioProject WithLanguageResults(string code, bool includingDrafts) => this;
 public AudioStatus AudioReadiness(string code) => new(false,"en · 1/2 AD audio","Missing audio");
// PRODUCTION_STATUS_METHOD
// PRODUCTION_STATUS_LIST
// PRODUCTION_EXPORT_PREDICATE
}
// PRODUCTION_STATUS_RECORD
class MainClass {
 static void Check(bool condition) { if (!condition) throw new Exception("Assertion failed"); }
 static void Main() {
  var p=new StudioProject();
  foreach(var text in new[]{"", " \n\t"}) {
   p.Transcript=new(){new(text)};p.Cues=new(){new(text)};p.Summary=text;
   foreach(var kind in new[]{"transcript","summary","descriptions","combined"}) Check(!p.CanExportText(kind));
   foreach(var kind in new[]{"transcript","summary","descriptions"}) {
    var result=new LanguageResult{Kind=kind,Payload=JsonSerializer.SerializeToElement(new {transcript=new[]{new{text}},cues=new[]{new{text}},summary=text})};
    Check(!result.HasExportableText);
   }
  }
  p.Transcript=new(){new("Dialogue")}; p.Summary="A👨‍👩‍👧‍👦e\u0301\n";
  Check(p.CanExportText("transcript")); Check(!p.CanExportText("combined"));
  Check(p.ContentStatus(0,"en")!.Complete && p.ContentStatus(0,"en")!.Title.Contains("1 Transcript segments"));
  Check(p.ContentStatus(1,"en")!.Title.Contains("4 Summary characters"));
  foreach(var tab in new[]{2,3,4}) Check(!p.ContentStatus(tab,"en")!.Complete && p.ContentStatus(tab,"en")!.Title.Contains("AD audio"));
  Check(p.ContentStatus(5,"en")==null);
  Console.WriteLine("PASS: actual Windows export predicates, result text gates and per-tab Unicode counts");
 }
}
