import AVFoundation

/// Records 16 kHz mono 16-bit WAV, which keeps uploads small and is accepted by Gemini.
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vox-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else {
            throw GeminiError(message: "Could not start recording. Check microphone access.")
        }
        self.recorder = recorder
        self.fileURL = url
    }

    /// Stops recording and returns the audio along with its duration in seconds.
    func stop() -> (data: Data, duration: TimeInterval)? {
        guard let recorder, let fileURL else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return (data, duration)
    }
}
