"""Exercise the production Swift and C# project ordering code."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WIN = ROOT.parent / 'Vidi-Studio-Windows/Vidi Studio Windows'
swift = '''
import Foundation
struct StudioProject {
 var id: String; var name: String; var duration: Double; var updatedAt: Double
 var isYouTubeURLProject: Bool; var folder: URL? { URL(fileURLWithPath: "/tmp/" + id) }
}
''' + (ROOT / 'VidiStudio/ProjectFolderIdentity.swift').read_text() + (ROOT / 'VidiStudio/ProjectListSort.swift').read_text() + '''
let projects = [StudioProject(id:"b",name:"Beta",duration:20,updatedAt:100,isYouTubeURLProject:false),
 StudioProject(id:"a",name:"alpha",duration:20,updatedAt:300,isYouTubeURLProject:true),
 StudioProject(id:"z",name:"Zebra",duration:60,updatedAt:200,isYouTubeURLProject:false)]
func ids(_ sort:ProjectListSort,_ history:[String:Double]=[:]) -> [String] { sort.sorted(projects,lastOpened:history).map(\\.id) }
precondition(ids(.lastOpened) == ["a","z","b"])
precondition(ids(.name) == ["a","b","z"])
precondition(ids(.duration) == ["z","a","b"])
precondition(ids(.type) == ["b","z","a"])
let suite="vidistudio-sort-test-"+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
defer { defaults.removePersistentDomain(forName:suite) }
ProjectOpenHistory.record(projects[0],defaults:defaults,now:1000)
let history=ProjectOpenHistory.read(defaults.data(forKey:ProjectOpenHistory.key)!)
precondition(ids(.lastOpened,history) == ["b","a","z"])
precondition(ProjectOpenHistory.read(Data("invalid".utf8)).isEmpty)
var invalid=projects[0];invalid.duration = .nan;invalid.updatedAt = .infinity
precondition(ProjectListSort.duration.sorted([invalid,projects[2]],lastOpened:[:]).first?.id == "z")
precondition(ProjectListSort.lastOpened.sorted([invalid,projects[2]],lastOpened:[:]).first?.id == "z")
precondition(ProjectListSort.name.sorted([projects[1],projects[0]].filter { !$0.isYouTubeURLProject },lastOpened:[:]).map(\\.id) == ["b"])
print("PASS: Swift project ordering, ties, filters, invalid metadata, opening history persistence and fallback")
'''
cs = '''
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using Vidi_Studio_Windows.Models;
var projects=new[]{new StudioProject("b","Beta",20,100,false),new StudioProject("a","alpha",20,300,true),new StudioProject("z","Zebra",60,200,false)};
void Check(string sort,string expected,JsonObject? history=null) {
 if(string.Join(",",ProjectListSort.Apply(projects,sort,history).Select(p=>p.Id))!=expected) throw new Exception(sort);
}
Check("opened","a,z,b");Check("name","a,b,z");Check("duration","z,a,b");Check("type","b,z,a");
Check("opened","b,a,z",new JsonObject{["/tmp/b"]=1000});
var invalid=new StudioProject("i","Invalid",double.NaN,double.PositiveInfinity,false);
if(ProjectListSort.Apply(new[]{invalid,projects[2]},"duration",null).First().Id!="z")throw new Exception("invalid duration");
if(ProjectListSort.Apply(new[]{invalid,projects[2]},"opened",null).First().Id!="z")throw new Exception("invalid date");
if(ProjectListSort.Apply(projects.Where(p=>!p.IsYouTube),"name",null).Count()!=2)throw new Exception("filter");
Console.WriteLine("PASS: Windows production project ordering, ties, filters, invalid metadata, opening history and fallback");
namespace Vidi_Studio_Windows.Models {
 public class StudioProject {
  public string Id,Name,Folder; public double Duration; public bool IsYouTube;
  public Dictionary<string,JsonElement>? Extra;
  public StudioProject(string id,string name,double duration,double updated,bool youtube) {
   Id=id;Name=name;Folder="/tmp/"+id;Duration=duration;IsYouTube=youtube;
   Extra=double.IsFinite(updated)?new(){["updatedAt"]=JsonSerializer.SerializeToElement(updated)}:null;
  }
 }
}
'''
with tempfile.TemporaryDirectory(prefix='vidistudio-project-sort-') as folder:
    path=Path(folder)
    (path/'main.swift').write_text(swift)
    subprocess.run(['xcrun','swiftc',str(path/'main.swift'),'-o',str(path/'swift-check')],check=True)
    subprocess.run([str(path/'swift-check')],check=True)
    (path/'Program.cs').write_text(cs)
    (path/'Check.csproj').write_text(f'<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Exe</OutputType><Nullable>enable</Nullable></PropertyGroup><ItemGroup><Compile Include="{WIN / "Models/ProjectListSort.cs"}"/></ItemGroup></Project>')
    subprocess.run(['dotnet','run','--project',str(path/'Check.csproj'),'-v:q'],check=True)
