"""Run the production time parser on the same boundary fixtures on both desktops."""
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WIN = ROOT.parent / 'Vidi-Studio-Windows/Vidi Studio Windows'
cases = [
    ('0', 0), ('83.5', 83.5), ('1:23.5', 83.5), ('01:02:03.500', 3723.5),
    (' 00:00:01.005 ', 1.005), ('7200', 7200), ('2:00:00', 7200),
    ('', None), ('-1', None), ('NaN', None), ('Infinity', None), ('1e2', None),
    ('1:60', None), ('1:60:00', None), ('1::2', None), ('1:2:3:4', None),
    ('0: 2', None), ('1,5', None), ('1.', None), ('.5', None), ('7200.001', None),
    ('9' * 400, None), ('1\n', 1), ('1\n2', None),
]
swift = (ROOT/'VidiStudio/JumpToTime.swift').read_text().split('struct JumpToTimeView:')[0].replace('import SwiftUI', '')
cs = 'using Vidi_Studio_Windows.Models;\n'
for text, expected in cases:
    literal = json.dumps(text)
    if expected is None:
        swift += f'precondition(JumpTime.parse({literal}, duration: 7200) == nil)\n'
        cs += f'if (JumpTime.Parse({literal}, 7200) != null) throw new Exception("Invalid time accepted");\n'
    else:
        swift += f'precondition(abs(JumpTime.parse({literal}, duration: 7200)! - {expected}) < 0.00001)\n'
        cs += f'if (Math.Abs(JumpTime.Parse({literal}, 7200)!.Value - {expected}) > 0.00001) throw new Exception("Wrong time");\n'
swift += '''
for duration in [0.0, -1, Double.nan, Double.infinity] {
    precondition(JumpTime.parse("0", duration: duration) == nil)
}
precondition(JumpTime.format(3723.5) == "01:02:03.500")
print("PASS: Swift time formats, fractions, boundaries and invalid input")
'''
cs += '''
foreach (var duration in new[] {0.0, -1, double.NaN, double.PositiveInfinity})
    if (JumpTime.Parse("0", duration) != null) throw new Exception("Invalid duration");
if (JumpTime.Format(3723.5) != "01:02:03.500") throw new Exception("Wrong format");
Console.WriteLine("PASS: C# time formats, fractions, boundaries and invalid input");
'''
with tempfile.TemporaryDirectory(prefix='vidistudio-jump-') as folder:
    path = Path(folder)
    (path/'main.swift').write_text(swift)
    subprocess.run(['xcrun', 'swiftc', str(path/'main.swift'), '-o', str(path/'swift-check')], check=True)
    subprocess.run([str(path/'swift-check')], check=True)
    (path/'Program.cs').write_text(cs)
    (path/'Check.csproj').write_text(f'<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Exe</OutputType><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup><ItemGroup><Compile Include="{WIN / "Models/JumpTime.cs"}"/></ItemGroup></Project>')
    subprocess.run(['dotnet', 'run', '--project', str(path/'Check.csproj'), '-v:q'], check=True)
