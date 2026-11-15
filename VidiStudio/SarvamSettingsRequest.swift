import Foundation

enum SarvamSettingsRequest {
    static func run(_ command: String, key: String = "", executable: URL? = nil, timeout: TimeInterval = 45) async throws -> Data {
        guard ["list-sarvam-models", "check-sarvam-key"].contains(command),
              let engine = executable ?? Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else { throw CocoaError(.executableNotLoadable) }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process(), output = Pipe()
            process.executableURL = engine
            process.arguments = [command]
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
            guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
            return data
        }.value
    }
}
