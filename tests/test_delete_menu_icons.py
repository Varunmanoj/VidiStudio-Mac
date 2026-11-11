"""Check the production Windows icon factory against destructive-action semantics."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
WIN=ROOT if (ROOT/'Vidi Studio Windows').is_dir() else ROOT.parent/'Vidi-Studio-Windows'

class DeleteMenuIcons(unittest.TestCase):
    def test_delete_actions_never_use_the_more_actions_glyph(self):
        if not shutil.which('dotnet'): self.skipTest('.NET SDK required')
        harness=r'''using System;
using Vidi_Studio_Windows.Views;
namespace Microsoft.UI.Xaml.Media { public class FontFamily { public FontFamily(string name){} } }
namespace Microsoft.UI.Xaml.Controls { public class FontIcon { public Microsoft.UI.Xaml.Media.FontFamily FontFamily {get;set;}=null!; public double FontSize {get;set;} public string Glyph {get;set;}=""; } }
class Program {
 static void Check(string glyph, params string[] actions) {
  foreach(var action in actions) {
   var icon=MenuIcons.Create(action);
   if(icon.Glyph!=glyph) throw new Exception($"{action}: expected U+{(int)glyph[0]:X4}, got U+{(int)icon.Glyph[0]:X4}");
  }
 }
 static void Main() {
  Check("\uE74D", "delete-project", "trash-project", "delete-transcript", "delete-summary", "delete-descriptions", "delete-current", "segment-delete-selected", "segment-one-delete", "Delete Project…", "Delete Transcript…", "Delete Summary…", "Delete Descriptions…", "Delete Segment…", "Delete Selected Segments…", "Move Project to Recycle Bin…", "Move to Recycle Bin", "Delete selected", "Delete segment");
  Check("\uE75C", "delete-content", "Choose Content to Delete…", "Choose What to Delete…");
  Check("\uE74F", "delete-narration", "segment-one-delete-audio", "Delete All Narration Audio…", "Delete Segment Audio…", "Delete narration");
  Check("\uE738", "Remove from List");
  Check("\uE712", "More Actions");
  Console.WriteLine("PASS: destructive IDs and titles use trash, eraser or audio removal; Remove from List and More Actions stay distinct");
 }
}'''
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)
            shutil.copyfile(WIN/'Vidi Studio Windows/Views/MenuIcons.cs',p/'MenuIcons.cs')
            (p/'Main.cs').write_text(harness)
            (p/'Test.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
            result=subprocess.run(['dotnet','run','--project',str(p/'Test.csproj')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

if __name__=='__main__':unittest.main()
