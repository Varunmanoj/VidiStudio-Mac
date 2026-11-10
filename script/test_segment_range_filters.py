"""Compile production desktop filter models and exercise selection/range boundaries."""
from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
MAC=ROOT/'VidiStudio Mac'; WIN=ROOT/'Vidi-Studio-Windows/Vidi Studio Windows'
if not MAC.is_dir():
 ROOT=Path('/Users/personal/Documents/GitHub/VidiStudio');MAC=ROOT/'VidiStudio Mac';WIN=ROOT/'Vidi-Studio-Windows/Vidi Studio Windows'
swift=(MAC/'VidiStudio/SegmentRangeFilter.swift').read_text()+r'''
let available: Set<String> = ["transcript:a", "transcript:b", "ad:c"]
func error(_ f: SegmentRangeFilter) -> String? { f.error(transcriptCount: 10, descriptionCount: 4, duration: 100, availableIDs: available) }
var f = SegmentRangeFilter()
assert(!f.isActive && f.matches(id:"other", number:99, isDescription:false, start:0,end:1))
f.mode = .selection
assert(error(f) != nil)
f.selectedIDs = ["transcript:a", "ad:c"]
assert(error(f) == nil)
assert(f.matches(id:"transcript:a",number:1,isDescription:false,start:0,end:1))
assert(f.matches(id:"ad:c",number:3,isDescription:true,start:8,end:10))
assert(!f.matches(id:"transcript:b",number:2,isDescription:false,start:1,end:2))
f.selectedIDs.insert("missing"); assert(error(f) != nil)
f.mode = .numberRanges
f.numberRanges = [.init(isDescription:false,start:"2",end:"4"), .init(isDescription:false,start:"8",end:"9"), .init(isDescription:true,start:"3",end:"3")]
assert(error(f) == nil)
for n in 1...10 { assert(f.matches(id:"any",number:n,isDescription:false,start:0,end:1) == ([2,3,4,8,9].contains(n))) }
assert(f.matches(id:"any",number:3,isDescription:true,start:90,end:91))
for (start,end) in [("0","2"),("4","2"),("1","11"),("2.5","3"),("","3"),("2,3","4")] {
 f.numberRanges = [.init(start:start,end:end)]; assert(error(f) != nil)
}
f.mode = .timeRanges; f.timeRanges = [.init(start:10,end:20),.init(start:30,end:40)]
assert(error(f) == nil)
assert(f.matches(id:"any",number:1,isDescription:false,start:9,end:11))
assert(!f.matches(id:"any",number:1,isDescription:false,start:1,end:10))
assert(!f.matches(id:"any",number:1,isDescription:false,start:20,end:30))
assert(f.matches(id:"any",number:1,isDescription:true,start:35,end:38))
f.timeMatch = .contained
assert(!f.matches(id:"any",number:1,isDescription:false,start:9,end:11))
assert(f.matches(id:"any",number:1,isDescription:false,start:10,end:20))
assert(!f.matches(id:"any",number:1,isDescription:false,start:19,end:31))
for (start,end) in [(-1.0,2.0),(2,2),(4,2),(1,101),(.nan,3)] {
 f.timeRanges = [.init(start:start,end:end)]; assert(error(f) != nil)
}
print("PASS: Swift modes, existing IDs, multiple checkbox selections, disjoint number/time ranges, boundaries and invalid values")
'''
cs=r'''
using System;
using System.Collections.Generic;
using Vidi_Studio_Windows.Models;
static void Check(bool value) { if (!value) throw new Exception("Filter model regression"); }
var ids = new HashSet<string>{"transcript:a","transcript:b","ad:c"};
string? Error(SegmentRangeFilter f) => f.Error(10,4,100,ids);
var f = new SegmentRangeFilter(); Check(!f.IsActive && f.Matches("any",99,false,0,1));
f.Mode="selection"; Check(Error(f)!=null); f.SelectedIds.UnionWith(new[]{"transcript:a","ad:c"});
Check(Error(f)==null && f.Matches("transcript:a",1,false,0,1) && !f.Matches("transcript:b",2,false,1,2));
var copy=f.Clone(); copy.SelectedIds.Add("missing"); Check(Error(copy)!=null && Error(f)==null);
f.Mode="numberRanges";
f.NumberRanges.AddRange(new[]{new SegmentRangeFilter.NumberRange{Start=2,End=4},new SegmentRangeFilter.NumberRange{Start=8,End=9},new SegmentRangeFilter.NumberRange{IsDescription=true,Start=3,End=3}});
Check(Error(f)==null);
for(var n=1;n<=10;n++) Check(f.Matches("any",n,false,0,1)==(n>=2&&n<=4||n>=8&&n<=9));
foreach(var pair in new[]{(0d,2d),(4d,2d),(1d,11d),(2.5,3d),(double.NaN,3d)}) { f.NumberRanges.Clear();f.NumberRanges.Add(new(){Start=pair.Item1,End=pair.Item2});Check(Error(f)!=null); }
f.Mode="timeRanges";f.TimeRanges.AddRange(new[]{new SegmentRangeFilter.TimeRange{Start=10,End=20},new SegmentRangeFilter.TimeRange{Start=30,End=40}});
Check(Error(f)==null && f.Matches("any",1,false,9,11) && !f.Matches("any",1,false,1,10) && !f.Matches("any",1,false,20,30));
f.Contained=true;Check(!f.Matches("any",1,false,9,11) && f.Matches("any",1,false,10,20));
foreach(var pair in new[]{(-1d,2d),(2d,2d),(4d,2d),(1d,101d),(double.NaN,3d)}) {f.TimeRanges.Clear();f.TimeRanges.Add(new(){Start=pair.Item1,End=pair.Item2});Check(Error(f)!=null);}
var combined=new SegmentFilter();combined.Ranges.Mode="selection";combined.Ranges.SelectedIds.Add("ad:c");combined.Origins.Add("ai");combined.Audio="withAudio";
var row=new Segment{Id="c",IsDescription=true,SegmentNumber=3,Start=30,End=32,Origin="ai"};
Check(combined.Matches(row,true) && !combined.Matches(row,false));row.Origin="manual";Check(!combined.Matches(row,true));
combined.Clear();Check(!combined.IsActive && combined.Matches(row,false));
Console.WriteLine("PASS: Windows matching, cloned dialog drafts, existing IDs, number/time boundaries, invalid values, and Origin/Audio intersection");
namespace Vidi_Studio_Windows.Models { public class Segment { public string Id="";public string Origin="";public bool IsDescription;public int SegmentNumber;public double Start,End; } }
'''
with tempfile.TemporaryDirectory(prefix='vidi-range-filter-') as folder:
 p=Path(folder);(p/'main.swift').write_text(swift);subprocess.run(['swiftc',str(p/'main.swift'),'-o',str(p/'swift-check')],check=True);subprocess.run([str(p/'swift-check')],check=True)
 (p/'Program.cs').write_text(cs)
 (p/'Check.csproj').write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Exe</OutputType><Nullable>enable</Nullable></PropertyGroup><ItemGroup><Compile Include="{WIN/'Models/SegmentRangeFilter.cs'}"/><Compile Include="{WIN/'Models/SegmentFilter.cs'}"/></ItemGroup></Project>''')
 subprocess.run(['dotnet','run','--project',str(p/'Check.csproj'),'-v:q'],check=True)
