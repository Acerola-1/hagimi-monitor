import Foundation
import Metal

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "30") ?? 30
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "both"
let cpuCount = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 8 : 8
guard seconds.isFinite, seconds > 0, seconds <= 120, (1...32).contains(cpuCount), ["cpu", "gpu", "both"].contains(mode) else { fatalError("bounded stress: seconds 1...120, workers 1...32, cpu/gpu/both") }
let deadline = ProcessInfo.processInfo.systemUptime + seconds
let group = DispatchGroup()
if mode == "cpu" || mode == "both" {
    for index in 0..<cpuCount {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            var acc = Double(index + 1)
            while ProcessInfo.processInfo.systemUptime < deadline {
                for n in 1..<10000 { acc = sqrt(acc + Double(n)) }
            }
            print("cpu-worker=\(index) checksum=\(acc)")
            group.leave()
        }
    }
}
if mode == "gpu" || mode == "both" {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
    let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void burn(device float *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {
        float v = float(i + 1) * 0.0001f;
        for (uint n = 0; n < 1024; n++) { v = sin(v) * 1.01f + cos(v * 0.9f); }
        out[i] = v;
    }
    """
    let library = try device.makeLibrary(source: source, options: nil)
    let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "burn")!)
    let count = 1 << 17
    let buffer = device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared)!
    var batches = 0
    var gpuSeconds = 0.0
    while ProcessInfo.processInfo.systemUptime < deadline {
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        for _ in 0..<8 {
            encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth * 4, height: 1, depth: 1))
            encoder.memoryBarrier(scope: .buffers)
        }
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        gpuSeconds += max(0, command.gpuEndTime - command.gpuStartTime)
        batches += 1
    }
    print("metal-device=\(device.name) batches=\(batches) gpu-seconds=\(gpuSeconds)")
}
group.wait()
print("completed mode=\(mode) seconds=\(seconds)")
