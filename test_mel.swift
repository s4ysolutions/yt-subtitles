#!/usr/bin/env swift

import Accelerate
import Foundation

print("Starting test...")

// Test mel filter bank creation
let fftSize = 512
let melBands = 64
let sampleRate = 16000
let minFreq: Float = 125.0
let maxFreq: Float = 7500.0

let nyquist = Float(sampleRate) / 2.0
let minMel = hzToMel(minFreq)
let maxMel = hzToMel(maxFreq)
print("minMel: \(minMel), maxMel: \(maxMel)")

var melPoints = [Float](repeating: 0, count: melBands + 2)
for i in 0..<melBands + 2 {
    melPoints[i] = melToHz(minMel + Float(i) * (maxMel - minMel) / Float(melBands + 1))
}
print("melPoints: \(melPoints)")

var filterBank = [[Float]](repeating: [Float](repeating: 0, count: melBands), count: fftSize / 2 + 1)

for k in 0..<fftSize / 2 + 1 {
    let freq = Float(k) * nyquist / Float(fftSize / 2)
    
    for j in 0..<melBands {
        if j + 2 < melPoints.count {
            if freq >= melPoints[j] && freq <= melPoints[j + 1] {
                filterBank[k][j] = (freq - melPoints[j]) / (melPoints[j + 1] - melPoints[j])
            } else if freq >= melPoints[j + 1] && freq <= melPoints[j + 2] {
                filterBank[k][j] = (melPoints[j + 2] - freq) / (melPoints[j + 2] - melPoints[j + 1])
            }
        }
    }
}

print("Filter bank created: \(filterBank.count) x \(filterBank[0].count)")
print("Test passed!")

func hzToMel(_ hz: Float) -> Float {
    2595.0 * log10(1.0 + hz / 700.0)
}

func melToHz(_ mel: Float) -> Float {
    700.0 * (pow(10.0, mel / 2595.0) - 1.0)
}