#!/usr/bin/env swift

import Accelerate
import Foundation

print("Starting full feature extraction test...")

let fftSize = 512
let windowSize = 400
let hopSize = 160
let melBands = 64
let melMinFreq: Float = 125.0
let melMaxFreq: Float = 7500.0
let logOffset: Float = 0.001

// Create mel filter bank
let nyquist = Float(16000) / 2.0
let minMel = hzToMel(melMinFreq)
let maxMel = hzToMel(melMaxFreq)

var melPoints = [Float](repeating: 0, count: melBands + 2)
for i in 0..<melBands + 2 {
    melPoints[i] = melToHz(minMel + Float(i) * (maxMel - minMel) / Float(melBands + 1))
}

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
print("Filter bank created")

// FFT setup
let log2n = vDSP_Length(log2(Float(fftSize)))
let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

// Window
var window = [Float](repeating: 0, count: windowSize)
vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

// Test with 1 second of audio
let samples = (0..<16000).map { i in sin(Float(i) * 2.0 * Float.pi * 440.0 / 16000.0) * 0.5 }
let numFrames = (samples.count - windowSize) / hopSize + 1
let framesNeeded = 96

var melSpectrogram = [[Float]](repeating: [Float](repeating: 0, count: melBands), count: min(numFrames, framesNeeded))

var real = [Float](repeating: 0, count: fftSize / 2 + 1)
var imag = [Float](repeating: 0, count: fftSize / 2 + 1)

print("Processing \(min(numFrames, framesNeeded)) frames...")

for frameIdx in 0..<min(numFrames, framesNeeded) {
    let offset = frameIdx * hopSize
    let frame = Array(samples[offset..<offset + windowSize])
    
    var windowed = [Float](repeating: 0, count: windowSize)
    vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(windowSize))
    
    var paddedReal = [Float](repeating: 0, count: fftSize)
    for i in 0..<windowSize {
        paddedReal[i] = windowed[i]
    }
    
    real.withUnsafeMutableBufferPointer { realPtr in
        imag.withUnsafeMutableBufferPointer { imagPtr in
            var splitComplex = DSPSplitComplex(
                realp: realPtr.baseAddress!,
                imagp: imagPtr.baseAddress!
            )
            
            var complexArray = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize / 2)
            for i in 0..<fftSize / 2 {
                complexArray[i] = DSPComplex(real: paddedReal[2*i], imag: paddedReal[2*i + 1])
            }
            
            complexArray.withUnsafeMutableBufferPointer { complexPtr in
                vDSP_ctoz(UnsafePointer<DSPComplex>(complexPtr.baseAddress!), 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
            }
            
            var magnitudes = [Float](repeating: 0, count: fftSize / 2 + 1)
            vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2 + 1))
            
            // Apply mel filter bank
            for melBand in 0..<melBands {
                var sum: Float = 0
                for k in 0..<magnitudes.count {
                    sum += magnitudes[k] * filterBank[k][melBand]
                }
                melSpectrogram[frameIdx][melBand] = log(sum + logOffset)
            }
        }
    }
}

print("Mel spectrogram shape: \(melSpectrogram.count) x \(melBands)")

// Create patch
var patch = [[Float]](repeating: [Float](repeating: 0, count: melBands), count: framesNeeded)
for f in 0..<framesNeeded {
    for b in 0..<melBands {
        if f < melSpectrogram.count {
            patch[f][b] = melSpectrogram[f][b]
        } else {
            patch[f][b] = 0
        }
    }
}

print("Patch created: \(patch.count) x \(patch[0].count)")
print("Test passed!")

vDSP_destroy_fftsetup(fftSetup)

func hzToMel(_ hz: Float) -> Float {
    2595.0 * log10(1.0 + hz / 700.0)
}

func melToHz(_ mel: Float) -> Float {
    700.0 * (pow(10.0, mel / 2595.0) - 1.0)
}