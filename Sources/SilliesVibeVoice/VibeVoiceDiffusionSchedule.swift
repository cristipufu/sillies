// DPM-Solver++ equations and scheduler reference: Copyright 2024 TSAIL Team and The HuggingFace Team.
// Adapted to bounded Swift/MLX inference under Apache 2.0; see Resources/Licenses/VibeVoice-DPMSolver-Apache-2.0.txt.
import Foundation
import MLX

/// Second-order DPM-Solver++ with velocity prediction and the publisher's cosine schedule.
struct VibeVoiceDiffusionSchedule {
  struct Step {
    let timestep: Int
    let signal: Float
    let noise: Float
    let sampleCoefficient: Float
    let predictionCoefficient: Float
    let differenceCoefficient: Float
  }
  let steps: [Step]
  private static let cosineOffset = 0.008
  private static let maximumBeta = 0.999

  init(trainingSteps: Int, inferenceSteps: Int) throws {
    guard (2...10_000).contains(trainingSteps), (2...100).contains(inferenceSteps),
      inferenceSteps <= trainingSteps
    else {
      throw VibeVoiceError.unsupportedConfiguration
    }
    func alphaBar(_ time: Double) -> Double {
      pow(cos((time + Self.cosineOffset) / (1 + Self.cosineOffset) * .pi / 2), 2)
    }
    var cumulative = Float(1)
    let sigmas = (0..<trainingSteps).map { index -> Double in
      let beta = Float(
        min(
          Self.maximumBeta,
          1 - alphaBar(Double(index + 1) / Double(trainingSteps))
            / alphaBar(Double(index) / Double(trainingSteps))))
      cumulative *= 1 - beta
      return Double(sqrt((1 - cumulative) / cumulative))
    }
    let timesteps = (1...inferenceSteps).reversed().map {
      Int(
        (Double(trainingSteps - 1) * Double($0) / Double(inferenceSteps)).rounded(.toNearestOrEven))
    }
    let selected = timesteps.map { sigmas[$0] } + [0]
    steps = timesteps.indices.map { index in
      let current = selected[index]
      let next = selected[index + 1]
      let signal = 1 / sqrt(1 + current * current)
      let noise = current * signal
      let nextSignal = 1 / sqrt(1 + next * next)
      let nextNoise = next * nextSignal
      let final = index == timesteps.count - 1
      let interval = final ? Double.infinity : log(current / next)
      let coefficient = -nextSignal * expm1(-interval)
      let difference: Double
      if index > 0, !final {
        let previousInterval = log(selected[index - 1] / current)
        difference = 0.5 * coefficient * interval / previousInterval
      } else {
        difference = 0
      }
      return Step(
        timestep: timesteps[index], signal: Float(signal), noise: Float(noise),
        sampleCoefficient: Float(nextNoise / noise), predictionCoefficient: Float(coefficient),
        differenceCoefficient: Float(difference))
    }
  }

  func advance(_ sample: MLXArray, velocity: MLXArray, step: Step, previous: inout MLXArray?)
    -> MLXArray
  {
    let prediction = sample * step.signal - velocity * step.noise
    var output = sample * step.sampleCoefficient + prediction * step.predictionCoefficient
    if let previous { output = output + (prediction - previous) * step.differenceCoefficient }
    previous = prediction
    return output
  }
}
