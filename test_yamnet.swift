#!/usr/bin/env swift

import CoreML
import Foundation

let modelURL = URL(fileURLWithPath: "/Users/dsa/.yt-subtitles/models/yamnet.mlpackage")

do {
    let compiledURL = try MLModel.compileModel(at: modelURL)
    print("Compiled: \(compiledURL.path)")
    
    let model = try MLModel(contentsOf: compiledURL)
    print("Model loaded successfully")
    
    // Check model description
    let inputDesc = model.modelDescription.inputDescriptionsByName
    let outputDesc = model.modelDescription.outputDescriptionsByName
    
    print("Inputs:")
    for (name, desc) in inputDesc {
        print("  \(name): \(desc)")
    }
    
    print("Outputs:")
    for (name, desc) in outputDesc {
        print("  \(name): \(desc)")
    }
    
    // Create test input
    let features = try MLMultiArray(shape: [1, 96, 64], dataType: .float16)
    for i in 0..<96 {
        for j in 0..<64 {
            features[[0, NSNumber(value: i), NSNumber(value: j)]] = NSNumber(value: 0.0)
        }
    }
    
    let input = try MLDictionaryFeatureProvider(dictionary: [
        "features": MLFeatureValue(multiArray: features)
    ])
    
    print("Running prediction...")
    let output = try model.prediction(from: input)
    print("Prediction successful")
    
    if let scores = output.featureValue(for: "Identity")?.multiArrayValue {
        print("Scores shape: \(scores.shape)")
        var bestScore: Float = 0
        var bestIdx = 0
        for i in 0..<scores.count {
            let score = scores[[0, NSNumber(value: i)]].floatValue
            if score > bestScore {
                bestScore = score
                bestIdx = i
            }
        }
        print("Best: idx=\(bestIdx), score=\(bestScore)")
    }
    
} catch {
    print("Error: \(error)")
}