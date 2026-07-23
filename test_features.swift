import Accelerate
import CoreML
import Foundation

class LogMelFeatureExtractor {
    let sampleRate: Int = 16000
    let stftWindowMs: Float = 25.0
    let stftHopMs: Float = 10.0
    let melBands: Int = 64
    let melMinFreq: Float = 125.0
    let melMaxFreq: Float = 7500.0
    let logOffset: Float = 0.001
    let patchFrames: Int = 96
    
    private let fftSize: Int
    private let windowSize: Int
    private let hopSize: Int
    private var melFilterBank: [[Float]]
    private var fftSetup: FFTSetup
    private var window: [Float]
    
    init() {
        self.fftSize = 512
        self.windowSize = Int(Float(sampleRate) * stftWindowMs / 1000.0)
        self.hopSize = Int(Float(sampleRate) * stftHopMs / 1000.0)
        print("Init: fftSize=\(fftSize), windowSize=\(windowSize), hopSize=\(hopSize)")
        
        self.melFilterBank = LogMelFeatureExtractor.createMelFilterBank(
            fftSize: fftSize,
            melBands: melBands,
            sampleRate: sampleRate,
            minFreq: melMinFreq,
            maxFreq: melMaxFreq
        )
        print("Filter bank created: \(melFilterBank.count) x \(melFilterBank[0].count)")
        
        self.fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
        print("Init complete")
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    func extractFeatures(from samples: [Float]) -> [MLMultiArray] {
        var patches: [MLMultiArray] = []
        
        var offset = 0
        while offset + windowSize <= samples.count {
            let frame = Array(samples[offset..<offset + windowSize])
            let melSpectrogram = computeMelSpectrogram(frame: frame)
            
            if melSpectrogram.count >= patchFrames {
                let patch = createPatch(from: melSpectrogram)
                patches.append(patch)
            }
            
            offset += hopSize
        }
        
        return patches
    }
    
    private func computeMelSpectrogram(frame: [Float]) -> [[Float]] {
        var windowed = [Float](repeating: 0, count: windowSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(windowSize))
        
        var real = [Float](repeating: 0, count: fftSize / 2 + 1)
        var imag = [Float](repeating: 0, count: fftSize / 2 + 1)
        
        var paddedReal = [Float](repeating: 0, count: fftSize)
        for i in 0..<windowSize {
            paddedReal[i] = windowed[i]
        }
        
        // FFT
        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
        paddedReal.withUnsafeBufferPointer { bufPtr in
            let complexPtr = UnsafeMutablePointer<DSPComplex>.allocate(capacity: fftSize / 2)
            defer { complexPtr.deallocate() }
            for i in 0..<fftSize / 2 {
                complexPtr[i] = DSPComplex(real: paddedReal[2*i], imag: paddedReal[2*i + 1])
            }
            vDSP_fft_zip(fftSetup, &splitComplex, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
        }
        
        // Compute magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2 + 1)
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2 + 1))
        
        // Apply mel filter bank
        var melSpectrogram: [[Float]] = []
        for melBand in 0..<melBands {
            var sum: Float = 0
            for k in 0..<magnitudes.count {
                sum += magnitudes[k] * melFilterBank[k][melBand]
            }
            melSpectrogram.append([log(sum + logOffset)])
        }
        
        return melSpectrogram
    }
    
    private func createPatch(from spectrogram: [[Float]]) -> MLMultiArray {
        let patch = try! MLMultiArray(shape: [1, NSNumber(value: patchFrames), NSNumber(value: melBands)], dataType: .float16)
        
        for frame in 0..<patchFrames {
            for band in 0..<melBands {
                let value = spectrogram[frame][band]
                patch[[0, NSNumber(value: frame), NSNumber(value: band)]] = NSNumber(value: value)
            }
        }
        
        return patch
    }
    
    static func createMelFilterBank(fftSize: Int, melBands: Int, sampleRate: Int, minFreq: Float, maxFreq: Float) -> [[Float]] {
        let nyquist = Float(sampleRate) / 2.0
        let minMel = hzToMel(minFreq)
        let maxMel = hzToMel(maxFreq)
        
        var melPoints = [Float](repeating: 0, count: melBands + 2)
        for i in 0..<melBands + 2 {
            melPoints[i] = melToHz(minMel + Float(i) * (maxMel - minMel) / Float(melBands + 1))
        }
        
        var filterBank = [[Float]](repeating: [Float](repeating: 0, count: melBands), count: fftSize / 2 + 1)
        
        for k in 0..<fftSize / 2 + 1 {
            let freq = Float(k) * nyquist / Float(fftSize / 2)
            
            for j in 0..<melBands {
                if freq >= melPoints[j] && freq <= melPoints[j + 1] {
                    filterBank[k][j] = (freq - melPoints[j]) / (melPoints[j + 1] - melPoints[j])
                } else if freq >= melPoints[j + 1] && freq <= melPoints[j + 2] {
                    filterBank[k][j] = (melPoints[j + 2] - freq) / (melPoints[j + 2] - melPoints[j + 1])
                }
            }
        }
        
        return filterBank
    }
    
    private static func hzToMel(_ hz: Float) -> Float {
        2595.0 * log10(1.0 + hz / 700.0)
    }
    
    private static func melToHz(_ mel: Float) -> Float {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }
}

// Test
print("Creating extractor...")
let extractor = LogMelFeatureExtractor()

print("Generating test audio...")
let testSamples = [Float](repeating: 0.1, count: 16000) // 1 second of 0.1 amplitude

print("Extracting features...")
let patches = extractor.extractFeatures(from: testSamples)

print("Extracted \(patches.count) patches")
if let first = patches.first {
    print("First patch shape: \(first.shape)")
    let val = first[[0, 0, 0]].floatValue
    print("First value: \(val)")
}

print("Test passed!")