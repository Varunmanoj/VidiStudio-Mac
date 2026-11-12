"""Run both production media formatters against shared duration fixtures."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from tests.test_segment_duration_bounds import declaration


class MediaTimeAccessibilityTests(unittest.TestCase):
    def test_native_formatters_agree_on_units_days_and_rounding(self):
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        windows = mac.parent / 'Vidi-Studio-Windows/Vidi Studio Windows'
        cases = [
            (0, '0 seconds', '0s'), (.001, '1 millisecond', '1ms'),
            (1.001, '1 second, 1 millisecond', '1s 1ms'),
            (336.396, '5 minutes, 36 seconds, 396 milliseconds', '5m 36s 396ms'),
            (59.9996, '1 minute', '1m'), (3600, '1 hour', '1h'),
            (86400, '1 day', '1d'),
            (90061.123, '1 day, 1 hour, 1 minute, 1 second, 123 milliseconds', '1d 1h 1m 1s 123ms'),
            (172800.5, '2 days, 500 milliseconds', '2d 500ms'),
            (-1, '0 seconds', '0s'),
        ]
        values = ', '.join(str(value) for value, _, _ in cases)
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            source = (mac / 'VidiStudio/NarrationTimeFormat.swift').read_text()
            content = (mac / 'VidiStudio/ContentView.swift').read_text()
            row = content[content.index('private struct TranscriptRow:'):content.index('private struct SegmentEditBatch:')]
            row = row.replace('    var color: Color { isDescription ? .purple : .blue }', '')
            source += '\n' + declaration((mac / 'VidiStudio/StudioModel.swift').read_text(), 'func timecode(')
            source += '\nstruct Segment: Hashable { var id = "fixture"; var start: Double; var end: Double; var text = "Test content" }\n' + row
            source += '''
precondition(timecode(90061.123) == "1d 01:01:01.123")
for ad in [false, true] {
    let row = TranscriptRow(segment: Segment(start: 90061.123, end: 90062.124), isDescription: ad)
    precondition(row.timingAnnouncement == "Start time: 1 day, 1 hour, 1 minute, 1 second, 123 milliseconds, End time: 1 day, 1 hour, 1 minute, 2 seconds, 124 milliseconds")
    precondition(row.accessibilityLabel(segmentNumber: 2).contains("Duration: 1 second, 1 millisecond"))
    precondition(row.playbackLabel.contains(row.timingAnnouncement))
}
''' 
            (tmp / 'main.swift').write_text(source + '\nlet values: [Double] = [' + values + ''']
let result = values.map { [NarrationTimeFormat.spokenDuration($0), NarrationTimeFormat.mediaDuration($0)] }
precondition(NarrationTimeFormat.spokenProjectDuration(nil) == "unavailable")
precondition(NarrationTimeFormat.spokenProjectDuration(.nan) == "unavailable")
precondition(NarrationTimeFormat.spokenProjectDuration(.infinity) == "unavailable")
precondition(NarrationTimeFormat.timestamp(90061.123) == "1d 01:01:01.123")
print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
''')
            compiled = subprocess.run(['xcrun', 'swiftc', str(tmp / 'main.swift'), '-module-cache-path', str(tmp / 'modules'), '-o', str(tmp / 'swift-check')], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            swift = subprocess.run([str(tmp / 'swift-check')], capture_output=True, text=True, check=True)
            dotnet = shutil.which('dotnet')
            self.assertIsNotNone(dotnet, 'The C# formatter must be exercised too')
            major = subprocess.check_output([dotnet, '--version'], text=True).split('.')[0]
            (tmp / 'check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net' + major + '.0</TargetFramework></PropertyGroup></Project>')
            (tmp / 'Format.cs').write_text((windows / 'Models/NarrationTimeFormat.cs').read_text())
            segment_source = (windows / 'Models/StudioProject.cs').read_text()
            segment_properties = '\n'.join(line.replace('[JsonIgnore] ', '') for line in segment_source.splitlines() if any('public string ' + name + ' =>' in line for name in ['StartLabel', 'EndLabel', 'Timing', 'StartAnnouncement', 'EndAnnouncement', 'TimingAnnouncement']))
            (tmp / 'SegmentTimes.cs').write_text('using System; using Vidi_Studio_Windows.Models; class SegmentTimes { public double Start = 90061.123; public double End = 90062.124;\n' + segment_properties + '\n}')
            (tmp / 'Program.cs').write_text('''using System;
using System.Linq;
using System.Text.Json;
using Vidi_Studio_Windows.Models;
var times = new SegmentTimes();
if (times.StartLabel != "1d 01:01:01.123" || times.EndLabel != "1d 01:01:02.124" || !times.TimingAnnouncement.Contains("Start time: 1 day") || !times.TimingAnnouncement.Contains("End time: 1 day")) throw new Exception("Segment boundary formatting");
var values = new double[] {''' + values + '''};
if (NarrationTimeFormat.SpokenProjectDuration(null) != "unavailable" || NarrationTimeFormat.SpokenProjectDuration(double.NaN) != "unavailable" || NarrationTimeFormat.SpokenProjectDuration(double.PositiveInfinity) != "unavailable" || NarrationTimeFormat.Timestamp(90061.123) != "1d 01:01:01.123") throw new Exception("Invalid/long duration handling");
Console.WriteLine("RESULT:" + JsonSerializer.Serialize(values.Select(value => new[] { NarrationTimeFormat.SpokenDuration(value), NarrationTimeFormat.MediaDuration(value) })));
''')
            env = os.environ | {'DOTNET_CLI_HOME': str(tmp), 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE': '1', 'DOTNET_NOLOGO': '1'}
            result = subprocess.run([dotnet, 'run', '--project', str(tmp / 'check.csproj'), '--verbosity', 'quiet'], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            csharp = json.loads(next(line[7:] for line in result.stdout.splitlines() if line.startswith('RESULT:')))
            expected = [[spoken, display] for _, spoken, display in cases]
            self.assertEqual(json.loads(swift.stdout), expected)
            self.assertEqual(csharp, expected)
