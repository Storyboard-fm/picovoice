//
//  TruckNoiseInjector.swift
//  storyboard-v2
//
//  Created by Ryan Token on 2/18/25.
//

import Foundation

class TruckNoiseInjector {
    private var truckNoiseSamples: [Int16]
    private var truckNoisePosition: Int = 0

    init(truckNoiseSamples: [Int16]) {
        self.truckNoiseSamples = truckNoiseSamples
    }

    func injectNoise(_ frame: [Int16]) -> [Int16] {
        return frame.map { int16Val in
            truckNoisePosition += 1
            if truckNoisePosition >= truckNoiseSamples.count {
                truckNoisePosition = 0
            }
            // Add the samples, clamping to Int16 bounds to prevent overflow
            return Int16(max(min(Int(int16Val) + Int(truckNoiseSamples[truckNoisePosition]), Int(Int16.max)), Int(Int16.min)))
        }
    }
}
