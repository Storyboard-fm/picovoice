//
//  RawAudioFileReader.swift
//  storyboard-v2
//
//  Created by Ryan Token on 2/18/25.
//

import Foundation

struct RawAudioFileReader {
    /// Reads a raw audio file and converts it to [Int16] samples
    /// - Parameter fileName: Name of the raw file in the bundle
    /// - Returns: Array of Int16 samples, or nil if file cannot be read
    static func readRawAudioFile(fileName: String) -> [Int16]? {
        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: "raw") else {
            print("Could not find \(fileName).raw in bundle")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let count = data.count / MemoryLayout<Int16>.stride

            // Create array of Int16 from the raw data
            var samples = [Int16](repeating: 0, count: count)
            _ = samples.withUnsafeMutableBytes { samplesPtr in
                data.copyBytes(to: samplesPtr)
            }

            return samples
        } catch {
            print("Error reading raw audio file: \(error)")
            return nil
        }
    }
}
