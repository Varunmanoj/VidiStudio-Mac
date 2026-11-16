import Foundation

enum SarvamSettingsRequest {
    static func run(_ command: String, key: String = "", executable: URL? = nil, timeout: TimeInterval = 45, arguments: [String] = []) async throws -> Data {
        guard ["list-sarvam-models", "check-sarvam-key", "preview-sarvam-sample"].contains(command),
              let engine = executable ?? Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else { throw CocoaError(.executableNotLoadable) }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process(), output = Pipe()
            process.executableURL = engine
            process.arguments = [command] + arguments
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "VIDISTUDIO_API_KEY")
            environment.removeValue(forKey: "VIDISTUDIO_SARVAM_API_KEY")
            if !key.isEmpty { environment["VIDISTUDIO_SARVAM_API_KEY"] = key }
            process.environment = environment
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            defer { watchdog.cancel() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = data.split(separator: 10).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }.last?["message"] as? String
                throw NSError(domain: "SarvamSample", code: 1, userInfo: [NSLocalizedDescriptionKey: message ?? "Sample could not be prepared."])
            }
            return data
        }.value
    }
}
