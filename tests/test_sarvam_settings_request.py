import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'darwin', 'Requires the native Swift compiler')
class SarvamSettingsRequestTests(unittest.TestCase):
    def test_native_requests_keep_credentials_private_and_bound_failures(self):
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            worker = folder / 'worker.py'
            worker.write_text('''#!/usr/bin/python3
import json, os, sys
print(json.dumps({'keyPresent': os.environ.get('VIDISTUDIO_SARVAM_API_KEY') == 'private-test-key', 'geminiAbsent': 'VIDISTUDIO_API_KEY' not in os.environ, 'args': sys.argv[1:]}))
''')
            slow = folder / 'slow.py'
            slow.write_text('#!/usr/bin/python3\nimport time\ntime.sleep(5)\n')
            worker.chmod(0o700); slow.chmod(0o700)
            main = folder / 'Main.swift'
            main.write_text('''import Foundation
@main struct Check {
    static func main() async throws {
        let worker = URL(fileURLWithPath: CommandLine.arguments[1])
        let slow = URL(fileURLWithPath: CommandLine.arguments[2])
        let data = try await SarvamSettingsRequest.run("check-sarvam-key", key: "private-test-key", executable: worker)
        let result = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(result["keyPresent"] as? Bool == true && result["geminiAbsent"] as? Bool == true)
        precondition(result["args"] as? [String] == ["check-sarvam-key"])
        let publicData = try await SarvamSettingsRequest.run("list-sarvam-models", executable: worker)
        let publicResult = try JSONSerialization.jsonObject(with: publicData) as! [String: Any]
        precondition(publicResult["keyPresent"] as? Bool == false)
        let start = Date()
        do { _ = try await SarvamSettingsRequest.run("list-sarvam-models", executable: slow, timeout: 0.2); fatalError("Missing timeout") } catch { }
        precondition(Date().timeIntervalSince(start) < 3)
        do { _ = try await SarvamSettingsRequest.run("unexpected-command", executable: worker); fatalError("Unrestricted command") } catch { }
        print("PASS: environment-only credentials, public refresh without keys, bounded failure and restricted commands")
    }
}
''')
            environment = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
            compiled = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(mac / 'build/sarvam-request-modules'), str(mac / 'VidiStudio/SarvamSettingsRequest.swift'), str(main), '-o', str(folder / 'check')], env=environment, capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(folder / 'check'), str(worker), str(slow)], capture_output=True, text=True, timeout=10, env=environment)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
