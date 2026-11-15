"""Compile production settings to exercise routing and serialization without OS credentials."""
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

def declaration(source, marker):
    start=source.index(marker); end=source.index('{',start)+1; depth=1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]

class SpeechProfiles(unittest.TestCase):
    def test_real_settings_routing_independence_and_credential_exclusion(self):
        if sys.platform != 'darwin': self.skipTest('Swift compiler required')
        root=Path(__file__).resolve().parents[1]
        mac=root if (root/'VidiStudio').exists() else root.parent/'VidiStudio Mac'
        settings=declaration((mac/'VidiStudio/StudioModel.swift').read_text(),'struct StudioSettings:')
        providers=(mac/'VidiStudio/SpeechProviderSettings.swift').read_text()
        stubs='''import Foundation
enum SummaryHighlightColor { static let defaultSentenceHex="#00F"; static let defaultWordHex="#FF0" }
enum ProjectSearchHighlight { static let defaultColor="#FF0" }
enum OnlineService { case gemini, sarvam }
enum NarrationVoiceFormatting { static func combinedLabel(voice:String,engine:String)->String { voice } }
enum SystemSpeechVoiceResolver {
    static let defaultVoiceIdentifier:String?=nil
    static let defaultVoiceDisplayName:String?=nil
    struct Voice { var language="en-US" }
    static func selectedVoice(named:String)->Voice? { nil }
}
enum PiperVoiceManager {
    static let shared=Self.manager
    case manager
    struct Voice { var languageLabel="English" }
    func voice(id:String)->Voice? { nil }
}
final class Credential {
    var value=""
    func read()->String? { value }
    func write(_ text:String)->Bool { value=text; return true }
}
enum KeychainStore {
    static let sarvam=Credential();static let gemini=Credential()
    static func read()->String? { gemini.read() }
    static func write(_ value:String) { _=gemini.write(value) }
}
'''
        main='''
@main struct Main {
    @MainActor static func main() throws {
        var settings=StudioSettings()
        settings.systemVoice="native-voice";settings.piperVoice="piper-voice"
        settings.systemSpeechRate=1.3;settings.systemSpeechPitch=1.2;settings.systemSpeechVolume=0.7
        settings.ttsMode="sarvam";settings.narrationPlayback="device"
        precondition(settings.narrationPlayback=="generated")
        precondition(settings.summarySpeech?.systemVoice=="native-voice")
        precondition(settings.resolvedSummarySettings.ttsMode=="system")
        precondition(settings.resolvedSummarySettings.systemSpeechRate==1.3)
        settings.summarySpeech?.engine="piper";settings.summarySpeech?.rate=1.8
        settings.summarySpeech?.pitch=0.8;settings.summarySpeech?.volume=0.4
        precondition(settings.resolvedSummarySettings.ttsMode=="piper")
        precondition(settings.resolvedSummarySettings.systemSpeechRate==1.8)
        precondition(settings.resolvedSummarySettings.systemSpeechPitch==0.8)
        precondition(settings.resolvedSummarySettings.systemSpeechVolume==0.4)
        precondition(settings.systemSpeechRate==1.3)
        settings.ttsMode="gemini"
        precondition(settings.resolvedSummarySettings.ttsMode=="piper")
        settings.ttsMode="system"
        precondition(settings.resolvedSummarySettings.systemSpeechRate==1.3)
        settings.ttsMode="gemini"
        precondition(settings.summarySpeech?.rate==1.8)
        settings.sarvamApiKey="sarvam-secret";settings.apiKey="gemini-secret"
        let bytes=try JSONEncoder().encode(settings)
        let encoded=String(decoding:bytes,as:UTF8.self)
        precondition(!encoded.contains("sarvam-secret") && !encoded.contains("gemini-secret"))
        precondition(!encoded.contains("sarvamApiKey") && !encoded.contains("apiKey"))
        let decoded=try JSONDecoder().decode(StudioSettings.self,from:bytes)
        precondition(decoded.summarySpeech==settings.summarySpeech)
        precondition(settings.sarvamSpeech.signature=="sarvam|shubh_enhi_ads|bulbul:v4-flash|en-IN|1.000|22050|wav|0.600")
        print("PASS: production local Summary routing, independent tuning, cloud lock, signatures and secret exclusion")
    }
}
'''
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder); (folder/'Engine/_internal').mkdir(parents=True); shutil.copyfile(mac/'engine/sarvam-voices.json',folder/'Engine/_internal/sarvam-voices.json'); source=folder/'Main.swift';source.write_text(stubs+"\n"+settings+"\n"+providers+"\n"+main)
            env=os.environ|{'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
            result=subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(mac/'build/speech-profile-modules'),str(source),'-o',str(folder/'check')],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(folder/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

if __name__=='__main__':unittest.main()
