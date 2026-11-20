"""Run production Mac and Windows error presentation with Developer mode on/off."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='vidi-errors-') as folder:
    root = Path(folder)
    source = (ROOT/'VidiStudio/UserFacingIssue.swift').read_text().split('\nenum UserFacingIssueReporter')[0]
    (root/'Issue.swift').write_text(source)
    (root/'main.swift').write_text('''
import Foundation
let diagnostic = "400 Invalid enum value standard, key=private-test-key"
let issue = UserFacingIssue.forEngine(command: "generate-summary", technicalDetails: diagnostic)
let normal = issue.message(developerMode: false, technicalDetails: diagnostic, apiKey: "private-test-key")
precondition(normal.contains("Your transcript is safe"))
precondition(!normal.contains("standard") && !normal.contains("400") && !normal.contains("Technical details"))
let developer = issue.message(developerMode: true, technicalDetails: diagnostic, apiKey: "private-test-key")
precondition(developer.contains("Invalid enum value standard") && developer.contains("[redacted]"))
precondition(!developer.contains("private-test-key"))
precondition(issue.message(developerMode: true, technicalDetails: nil, apiKey: "") == normal)
let duplicate = "This project already exists. Please continue with the existing project or delete the existing project before continuing."
let local = UserFacingIssue.forEngine(command: "import-video", technicalDetails: duplicate)
let youtube = UserFacingIssue.forEngine(command: "import-youtube", technicalDetails: duplicate)
precondition(local.title == "Project Already Exists" && local.message.contains("All Projects") && local.message.contains("rename"))
precondition(youtube.title == local.title && youtube.message.contains("YouTube") && youtube.message.contains("All Projects"))
let preflight = UserFacingIssue.duplicateProject(isYouTube: false, projectName: "Example Video")
precondition(preflight.title == local.title && preflight.message.contains("Example Video"))
print("Mac error presentation: generic off, diagnostic on, credential redacted")
''')
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(root/'modules'), str(root/'Issue.swift'), str(root/'main.swift'), '-o', str(root/'check')], check=True)
    subprocess.run([str(root/'check')], check=True)
    windows = ROOT.parent/'Vidi-Studio-Windows/Vidi Studio Windows/Services/ProcessingException.cs'
    (root/'Check.csproj').write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup><ItemGroup><Compile Include="{windows}" /></ItemGroup></Project>''')
    (root/'Program.cs').write_text('''
using System;
using Vidi_Studio_Windows.Services;
var diagnostic = "400 Invalid enum value standard, key=private-test-key";
var error = new ProcessingException(diagnostic, command: "generate-summary");
var normal = error.DisplayMessage(false, "private-test-key");
if (!normal.Contains("Your transcript is safe") || normal.Contains("standard") || normal.Contains("400") || normal.Contains("Technical details")) throw new Exception("Non-developer details leaked");
var developer = error.DisplayMessage(true, "private-test-key");
if (!developer.Contains("Invalid enum value standard") || !developer.Contains("[redacted]") || developer.Contains("private-test-key")) throw new Exception("Developer detail/redaction failed");
var duplicate = "This project already exists. Please continue with the existing project or delete the existing project before continuing.";
var local = new ProcessingException(duplicate, command: "import-video");
var youtube = new ProcessingException(duplicate, command: "import-youtube");
if (!local.IsDuplicateProject || !local.Message.Contains("All Projects") || !local.Message.Contains("rename")) throw new Exception("Local duplicate guidance missing");
if (!youtube.IsDuplicateProject || !youtube.Message.Contains("YouTube") || !youtube.Message.Contains("All Projects")) throw new Exception("YouTube duplicate guidance missing");
if (new ProcessingException(duplicate, command: "generate-summary").IsDuplicateProject) throw new Exception("Unrelated operation treated as a duplicate project");
Console.WriteLine("Windows error presentation: generic off, diagnostic on, credential redacted");
namespace Vidi_Studio_Windows.Services { public static class SpeechService { public static string FriendlyMessage(string text) => text; } }
''')
    subprocess.run(['dotnet', 'run', '--project', str(root/'Check.csproj'), '--verbosity', 'quiet'], check=True)
