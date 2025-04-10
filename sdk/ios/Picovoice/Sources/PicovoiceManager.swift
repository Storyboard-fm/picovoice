//
//  Copyright 2018-2023 Picovoice Inc.
//  You may not use this file except in compliance with the license. A copy of the license is located in the "LICENSE"
//  file accompanying this source.
//  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
//  an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
//  specific language governing permissions and limitations under the License.
//

import AVFoundation
import ios_voice_processor
import Porcupine
import Rhino

/// High-level iOS binding for Picovoice end-to-end platform. It handles recording audio
/// from microphone, processes it in real-time using Picovoice, and notifies the
/// client upon detection of the wake word or completion of in voice command inference.
public class PicovoiceManager {
    private var picovoice: Picovoice?
    private var truckNoiseInjector: TruckNoiseInjector?

    private var frameListener: VoiceProcessorFrameListener?
    private var errorListener: VoiceProcessorErrorListener?

    private var isListening: Bool = false

    public var contextInfo: String {
        get {
            return (self.picovoice != nil) ? self.picovoice!.contextInfo : ""
        }
    }

    public var wakeWordSensitivity: Double = 0.3

    /// Constructor.
    ///
    /// - Parameters:
    ///   - accessKey: The AccessKey obtained from Picovoice Console (https://console.picovoice.ai).
    ///   - keywordPath: Absolute paths to keyword model file.
    ///   - onWakeWordDetection: A callback that is invoked upon detection of the keyword.
    ///   - contextPath: Absolute path to file containing context parameters. A context represents
    ///   the set of expressions (spoken commands), intents, and intent arguments (slots) within a domain of interest.
    ///   - onInference: A callback that is invoked upon completion of intent inference.
    ///   - porcupineModelPath: Absolute path to file containing model parameters.
    ///   - porcupineSensitivity: Sensitivity for detecting keywords. Each value should be a number within [0, 1].
    ///   A higher sensitivity results in fewer misses at the cost of increasing the false alarm rate.
    ///   - rhinoModelPath: Absolute path to file containing model parameters.
    ///   - rhinoSensitivity: Inference sensitivity. It should be a number within [0, 1]. A higher sensitivity value
    ///   results in fewer misses at the cost of (potentially) increasing the erroneous inference rate.
    ///   - endpointDurationSec: Endpoint duration in seconds. An endpoint is a chunk of silence at the end of an
    ///   utterance that marks the end of spoken command. It should be a positive number within [0.5, 5].
    ///   A lower endpoint duration reduces delay and improves responsiveness.
    ///   A higher endpoint duration assures Rhino doesn't return inference pre-emptively
    ///   in case the user pauses before finishing the request.
    ///   - requireEndpoint: If set to `true`, Rhino requires an endpoint (a chunk of silence) after the spoken command.
    ///   If set to `false`, Rhino tries to detect silence, but if it cannot, it still will provide
    ///   inference regardless. Set to `false` only if operating in an environment with overlapping speech
    ///   (e.g. people talking in the background).
    ///   - processErrorCallback: A callback that is invoked if there is an error while processing audio.
    ///
    /// - Throws: PicovoiceError if unable to initialize
    public init(
            accessKey: String,
            keywordPaths: [String],
            shouldInjectTruckNoise: Bool,
            onWakeWordDetection: @escaping ((Int32) -> Void),
            contextPath: String,
            onInference: @escaping ((Inference) -> Void),
            porcupineModelPath: String? = nil,
            porcupineSensitivities: [Float32] = [0.5],
            rhinoModelPath: String? = nil,
            rhinoSensitivity: Float32 = 0.5,
            endpointDurationSec: Float32 = 1.0,
            requireEndpoint: Bool = true,
            processErrorCallback: ((Error) -> Void)? = nil
    ) throws {
        wakeWordSensitivity = Double(porcupineSensitivities.first ?? 0.5)
        picovoice = try Picovoice(
                accessKey: accessKey,
                keywordPaths: keywordPaths,
                onWakeWordDetection: onWakeWordDetection,
                contextPath: contextPath,
                onInference: onInference,
                porcupineModelPath: porcupineModelPath,
                porcupineSensitivities: porcupineSensitivities,
                rhinoModelPath: rhinoModelPath,
                rhinoSensitivity: rhinoSensitivity,
                endpointDurationSec: endpointDurationSec,
                requireEndpoint: requireEndpoint
        )
        print("Initialized pico with wake word sensitivity: \(porcupineSensitivities)")

        if shouldInjectTruckNoise {
            print("Will try to add truck noise to the pico voice processor")
            if let truckNoiseSamples = RawAudioFileReader.readRawAudioFile(fileName: "truck-noise") {
                print("Read the truck-noise raw audio file; truckNoiseInjector is ready to go")
                truckNoiseInjector = TruckNoiseInjector(truckNoiseSamples: truckNoiseSamples)
            } else {
                print("Could not read the truck-noise raw audio file; truck noise will not be injected")
            }
        }

        self.errorListener = VoiceProcessorErrorListener({ error in
            guard let callback = processErrorCallback else {
                print("\(error.localizedDescription)")
                return
            }

            callback(PicovoiceError(error.localizedDescription))
        })

        self.frameListener = VoiceProcessorFrameListener({ frame in
            guard let picovoice = self.picovoice else {
                return
            }

            let processedFrame: [Int16]
            if shouldInjectTruckNoise, let injector = self.truckNoiseInjector {
                processedFrame = injector.injectNoise(frame)
            } else {
                processedFrame = frame
            }

            do {
                try picovoice.process(pcm: processedFrame)
            } catch {
                guard let callback = processErrorCallback else {
                    print("\(error.localizedDescription)")
                    return
                }

                callback(error)
            }
        })
    }

    deinit {
        delete()
    }

    /// Releases native resources that were allocated to PicovoiceManager
    public func delete() {
        self.picovoice?.delete()
        self.picovoice = nil
    }

    /// Resets the internal state of PicovoiceManager. It can be called to
    /// return to the wake word detection state before an inference has completed.
    ///
    /// - Throws: PicovoiceError if unable to reset
    public func reset(shouldResetFrameListeners: Bool = true) throws {
        guard let picovoice else {
            throw PicovoiceInvalidStateError("Unable to reset - resources have been released.")
        }

        try picovoice.reset()
        try start(shouldResetFrameListeners: shouldResetFrameListeners)
    }

    ///  Starts recording audio from the microphone and Picovoice processing loop.
    ///
    /// - Throws: PicovoiceError if unable to start recording
    public func start(shouldResetFrameListeners: Bool = true) throws {
        guard self.picovoice != nil else {
            throw PicovoiceInvalidStateError("Unable to start - resources have been released.")
        }

        print("Starting pico with sensitivity of \(wakeWordSensitivity); resetting frame listeners? \(shouldResetFrameListeners)")

        if shouldResetFrameListeners {
            // First, ensure VoiceProcessor is fully stopped
            if VoiceProcessor.instance.isRecording {
                print("Pico VoiceProcessor was still recording, stopping first")
                try? VoiceProcessor.instance.stop()
            }

            // Clear all existing listeners
            VoiceProcessor.instance.clearFrameListeners()
            VoiceProcessor.instance.clearErrorListeners()
        }

        // Add our listeners fresh
        VoiceProcessor.instance.addErrorListener(errorListener!)
        VoiceProcessor.instance.addFrameListener(frameListener!)

        do {
            print("Attempting to start pico VoiceProcessor")
            try VoiceProcessor.instance.start(
                frameLength: Porcupine.frameLength,
                sampleRate: Porcupine.sampleRate
            )
            print("Successfully started pico VoiceProcessor")
            isListening = true
        } catch {
            print("Error starting pico: \(error)")
            throw PicovoiceError(error.localizedDescription)
        }
    }

    /// Stop audio recording and processing loop
    ///
    /// - Throws: PicovoiceError if unable to stop recording
    public func stop() throws {
        guard let picovoice = self.picovoice else {
            throw PicovoiceInvalidStateError("Unable to stop - resources have been released.")
        }

        if isListening {
            print("Stopping pico VoiceProcessor and clearing listeners")
            VoiceProcessor.instance.clearFrameListeners()
            VoiceProcessor.instance.clearErrorListeners()

            if VoiceProcessor.instance.isRecording {
                try VoiceProcessor.instance.stop()
            }

            isListening = false
        }

        try picovoice.reset()
    }
}
