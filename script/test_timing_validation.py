from pathlib import Path
import subprocess, tempfile, wave, hashlib
r=Path(__file__).resolve().parents[2];s=(r/'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
def func(name):
 a=s.index('private func '+name+'(');b=s.index('{',a);d=1;c=b+1
 while d:
  if s[c]=='{':d+=1
  if s[c]=='}':d-=1
  c+=1
 return s[a:c]
source='''import Foundation
struct Segment { var id: String; var start: Double; var end: Double; var text: String = "sample" }
struct TranscriptRow { var segment: Segment; var isDescription: Bool; var id: String { (isDescription ? "ad:" : "transcript:") + segment.id } }
'''+ '\n'.join(func(n) for n in ('preciseSegmentTimecode','segmentExcerpt','segmentValidationTargets','segmentValidationErrors'))+'''
func row(_ id: String, _ s: Double, _ e: Double, _ ad: Bool = false) -> TranscriptRow { TranscriptRow(segment: Segment(id: id, start: s, end: e), isDescription: ad) }
let current = row("same", 1, 63)
let rows = [current, row("last", 40, 44,true), row("same", 4,8.5,true), row("dialogue",39,39.5), row("next",63,65)]
assert(segmentValidationTargets(for: current, among: rows).map(\\.id) == ["ad:same","transcript:dialogue","ad:last"])
assert(segmentValidationErrors(for: current, among: rows, duration: 100).count == 3)
let errors = segmentValidationErrors(for: current, among: rows, duration: 100)
assert(errors[0].hasPrefix("Overlaps audio description segment #2 00:00:04.000 to 00:00:08.500:"))
assert(errors[1].hasPrefix("Overlaps transcript segment #2 00:00:39.000 to 00:00:39.500:"))
assert(errors[2].hasPrefix("Overlaps audio description segment #1 00:00:40.000 to 00:00:44.000:"))
let bulkRows = [rows[3], rows[1], rows[2], current, rows[4]]
assert(segmentValidationErrors(for: current, among: bulkRows, duration:100, numberingRows:rows) == errors)

assert(segmentValidationTargets(for: row("edit",8.5,10), among: [row("touch-left",4,8.5,true),row("touch-right",10,12)]).isEmpty)
assert(segmentValidationTargets(for: row("bad",.nan,3), among: rows).isEmpty)
assert(segmentValidationErrors(for: row("bad",2,1), among: [], duration:100) == ["End time must be after start time."])
assert(segmentValidationErrors(for: row("bad",0,101), among: [], duration:100).first!.contains("video duration"))
assert(segmentValidationErrors(for: current, among:[current], duration:100).isEmpty)
assert(segmentValidationTargets(for: row("edit",0,10), among:[row("z",1,2),row("a",1,3)]).map(\\.id) == ["transcript:a","transcript:z"])
print("PASS: actual Swift validation functions: mixed conflicts, per-kind segment numbers, bulk draft numbering, same-ID cross-type rows, chronological order, adjacency, nonfinite and local errors")
'''
with tempfile.TemporaryDirectory(prefix='vidi-274-validation-') as d:
 path=Path(d);(path/'main.swift').write_text(source)
 subprocess.run(['swiftc',str(path/'main.swift'),'-o',str(path/'check')],check=True)
 subprocess.run([str(path/'check')],check=True)
assets=[r/'VidiStudio Mac/VidiStudio/Sounds/Buzzer1.wav',r/'Vidi-Studio-Windows/Vidi Studio Windows/Assets/Sounds/Buzzer1.wav']
assert len({hashlib.sha256(p.read_bytes()).hexdigest() for p in assets})==1
with wave.open(str(assets[0])) as f: print(f'PASS: identical bundled WAV copies; {f.getnframes()/f.getframerate():.3f}s, {f.getnchannels()} channel(s)')
