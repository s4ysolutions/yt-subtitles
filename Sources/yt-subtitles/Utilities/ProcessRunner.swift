import Foundation

enum ProcessError: LocalizedError {
    case missingExecutable(String)
    case nonZeroExit(executable: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            "Missing prerequisite: \(name). Install with: brew install \(name)"
        case .nonZeroExit(let exe, let code, let stderr):
            "\(exe) exited with code \(code): \(stderr)"
        }
    }
}

enum ProcessRunner {
    /// Run an executable (resolved from PATH) and return its output. Throws on non-zero exit.
    @discardableResult
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        // Run entire process lifecycle on a DispatchQueue to avoid blocking
        // Swift concurrency's cooperative thread pool with waitUntilExit().
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [executable] + arguments
                if let env = environment {
                    process.environment = env
                }

                process.standardInput = FileHandle.nullDevice
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Read both pipes concurrently to avoid buffer deadlock.
                // If read sequentially, stdout readToEnd blocks until ffmpeg exits,
                // but ffmpeg may be blocked on full stderr buffer → deadlock.
                var stdoutData: Data?
                var stderrData: Data?
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    stdoutData = try? stdoutPipe.fileHandleForReading.readToEnd()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    stderrData = try? stderrPipe.fileHandleForReading.readToEnd()
                    group.leave()
                }
                group.wait()

                process.waitUntilExit()

                let stdout = String(data: stdoutData ?? Data(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrData ?? Data(), encoding: .utf8) ?? ""
                let exitCode = process.terminationStatus

                if exitCode != 0 {
                    continuation.resume(throwing: ProcessError.nonZeroExit(
                        executable: executable,
                        exitCode: exitCode,
                        stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } else {
                    continuation.resume(returning: (exitCode, stdout, stderr))
                }
            }
        }
    }

    /// Check if an executable exists on PATH.
    static func isOnPath(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
