"""Run production Mac and Windows error presentation with Developer mode on/off."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='vidi-errors-') as folder:
    root = Path(folder)
    source = (ROOT/'VidiStudio/UserFacingIssue.swift').read_text().split('\nenum UserFacingIssueReporter')[0]
    connection = (ROOT/'VidiStudio/OnlineRequirements.swift').read_text().split('\n/// Pure requirements')[0]
    model = (ROOT/'VidiStudio/StudioModel.swift').read_text()
    banner = model[model.index('struct AIServiceIssue:'):model.index('\nstruct NarrationFailureReport:')]
    (root/'Issue.swift').write_text(source + '\n' + connection + '\n' + banner +
        '\nstruct YouTubeVideo { static let privateVideoMessage = "Private YouTube videos are not supported."; static let privateAnalysisMessage = "Private YouTube video analysis is not supported." }\n')
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
let denied = "403 PERMISSION_DENIED. The caller does not have permission"
let privateVideo = UserFacingIssue.forEngine(command: "transcribe", technicalDetails: denied, connection: .googleSignIn, failureKind: "private-youtube-video")
precondition(privateVideo.title == "AI Analysis Unavailable" && privateVideo.message == YouTubeVideo.privateAnalysisMessage)
precondition(AIServiceIssue.detect(denied, connection: .googleSignIn, failureKind: "private-youtube-video") == nil)
let vertex = UserFacingIssue.forEngine(command: "generate-summary", technicalDetails: denied, connection: .googleSignIn)
precondition(vertex.title == "Vertex AI Access Needs Attention" && vertex.message.contains("Cloud project"))
precondition(AIServiceIssue.detect(denied, connection: .googleSignIn)?.message == vertex.message)
let express = UserFacingIssue.forEngine(command: "transcribe", technicalDetails: denied, connection: .express)
precondition(express.message.contains("Vertex AI Express API key"))
let bucket = "403 PERMISSION_DENIED: storage.objects.get for service-123@gcp-sa-aiplatform.iam.gserviceaccount.com"
precondition(UserFacingIssue.forEngine(command: "transcribe", technicalDetails: bucket, connection: .googleSignIn).title == "Vertex AI Needs Video Access")
precondition(AIServiceIssue.detect(bucket, connection: .googleSignIn) == nil)
let privateValue = ProjectEditorWindowValue.preferredWindow("private", isPrivate: true)
precondition(ProjectEditorWindowValue.projectID(from: privateValue) == "private")
precondition(ProjectEditorWindowValue.permitsPrivateProject(privateValue, projectID: "private"))
precondition(!ProjectEditorWindowValue.permitsPrivateProject(privateValue, projectID: "other"))
precondition(!ProjectEditorWindowValue.permitsPrivateProject("private", projectID: "private"))
precondition(!ProjectEditorWindowValue.permitsPrivateProject(ProjectEditorWindowValue.newWindow(for: "private"), projectID: "private"))
precondition(ProjectEditorWindowValue.replacingProject(in: privateValue, with: "beta") == "beta")
let extraPrivateWindow = ProjectEditorWindowValue.newWindow(for: "private", privateYouTubeApproved: true)
precondition(extraPrivateWindow != privateValue)
precondition(ProjectEditorWindowValue.permitsPrivateProject(extraPrivateWindow, projectID: "private"))
precondition(!ProjectEditorWindowValue.permitsPrivateProject(extraPrivateWindow, projectID: "other"))
print("Mac error presentation: generic off, diagnostic on, credential redacted")
''')
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(root/'modules'), str(root/'Issue.swift'), str(ROOT/'VidiStudio/ProjectEditorWindowValue.swift'), str(root/'main.swift'), '-o', str(root/'check')], check=True)
    subprocess.run([str(root/'check')], check=True)
    windows = ROOT.parent/'Vidi-Studio-Windows/Vidi Studio Windows/Services/ProcessingException.cs'
    windows_model = (windows.parents[1]/'Models/StudioProject.cs').read_text()
    detector = windows_model[windows_model.index('public static class AIServiceIssueDetector'):windows_model.index('/// <summary>The summary shown for narration status')]
    (root/'Detector.cs').write_text('using System;\nusing Vidi_Studio_Windows.Services;\nnamespace Vidi_Studio_Windows.Models;\n' + detector)
    (root/'Check.csproj').write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup><ItemGroup><Compile Include="{windows}" /></ItemGroup></Project>''')
    (root/'Program.cs').write_text('''
using System;
using Vidi_Studio_Windows.Services;
using Vidi_Studio_Windows.Models;
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
const string denied = "403 PERMISSION_DENIED. The caller does not have permission";
var privateVideo = new ProcessingException(denied, command: "transcribe", connection: AiConnection.GoogleSignIn, failureKind: "private-youtube-video");
if (!privateVideo.IsMediaAccessFailure || privateVideo.IssueTitle != "AI Analysis Unavailable" || privateVideo.Message != YouTubeVideo.PrivateAnalysisMessage) throw new Exception("Private YouTube guidance missing");
var vertex = new ProcessingException(denied, command: "generate-summary", connection: AiConnection.GoogleSignIn);
if (vertex.IsMediaAccessFailure || !vertex.Message.Contains("Cloud project") || AIServiceIssueDetector.Detect(denied, AiConnection.GoogleSignIn)?.Message != vertex.Message) throw new Exception("Vertex project guidance missing");
if (!new ProcessingException(denied, command: "transcribe", connection: AiConnection.Express).Message.Contains("Vertex AI Express API key")) throw new Exception("Express key guidance missing");
var bucket = new ProcessingException("403 PERMISSION_DENIED: storage.objects.get for service-123@gcp-sa-aiplatform.iam.gserviceaccount.com", command: "transcribe", connection: AiConnection.GoogleSignIn);
if (!bucket.IsMediaAccessFailure || bucket.IssueTitle != "Vertex AI Needs Video Access") throw new Exception("Cloud object guidance missing");
Console.WriteLine("Windows error presentation: generic off, diagnostic on, credential redacted");
namespace Vidi_Studio_Windows.Services {
    internal enum AiConnection { Developer, GoogleSignIn, Express }
    internal static class YouTubeVideo { internal const string PrivateVideoMessage = "Private YouTube videos are not supported."; internal const string PrivateAnalysisMessage = "Private YouTube video analysis is not supported."; }
    public static class SpeechService { public static string FriendlyMessage(string text) => text; }
}
''')
    subprocess.run(['dotnet', 'run', '--project', str(root/'Check.csproj'), '--verbosity', 'quiet'], check=True)
