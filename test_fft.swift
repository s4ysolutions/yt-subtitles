#!/usr/bin/env swift

import Accelerate
import Foundation

print("Starting FFT test...")

let fftSize = 512
let windowSize = 400
let hopSize = 160

// Create a simple sine wave
let samples = (0..<16000).map { i in sin(Float(i) * 2.0 * Float.pi * 440.0 / 16000.0) * 0.5 }
print("Created \(samples.count) samples")

// Create FFT setup
let log2n = vDSP_Length(log2(Float(fftSize)))
let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
print("FFT setup created")

// Create window
var window = [Float](repeating: 0, count: windowSize)
vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
print("Window created")

// Process one frame
let frame = Array(samples[0..<windowSize])
var windowed = [Float](repeating: 0, count: windowSize)
vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(windowSize))
print("Windowed frame created")

// Zero-pad to fftSize
var paddedReal = [Float](repeating: 0, count: fftSize)
for i in 0..<windowSize {
    paddedReal[i] = windowed[i]
}

// FFT
var real = [Float](repeating: 0, count: fftSize / 2 + 1)
var imag = [Float](repeating: 0, count: fftSize / 2 + 1)

print("Running FFT...")

real.withUnsafeMutableBufferPointer { realPtr in
    imag.withUnsafeMutableBufferPointer { imagPtr in
        var splitComplex = DSPSplitComplex(
            realp: realPtr.baseAddress!,
            imagp: imagPtr.baseAddress!
        )
        
        // Convert real to complex
        var complexArray = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize / 2)
        for i in 0..<fftSize / 2 {
            complexArray[i] = DSPComplex(real: paddedReal[2*i], imag: paddedReal[2*i + 1])
        }
        
        complexArray.withUnsafeMutableBufferPointer { complexPtr in
            vDSP_ctoz(UnsafePointer<DSPComplex>(complexPtr.baseAddress!), 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            
            // FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
            
            // Get magnitudes
            var magnitudes = [Float](repeating: 0, count: fftSize / 2 + 1)
            vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2 + 1))
            
            print("FFT done! Magnitudes[0..10]: \(magnitudes[0..<10])")
        }
    }
}

vDSP_destroy_fftsetup(fftSetup)
print("Test passed!")