import Darwin
import Foundation
import Metal
import MetalPerformanceShaders

/// The measurements behind the hardware test. Each one targets what local LLMs lean on:
/// GPU matrix math (reading the prompt), memory bandwidth (generating tokens), disk (loading models).
/// All of them are blocking and meant to run off the main thread.
enum HardwareBenchmarks {
    private static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    // MARK: CPU

    /// Mandelbrot rows: plain floating-point work that fits in cache, so it measures the cores.
    private static func mandelbrotRow(_ y: Int, width: Int = 256, height: Int = 256) -> Int {
        var iterations = 0
        let ci = Double(y) / Double(height) * 2.4 - 1.2
        for x in 0..<width {
            let cr = Double(x) / Double(width) * 3.2 - 2.2
            var zr = 0.0, zi = 0.0, n = 0
            while n < 200 && zr * zr + zi * zi < 4 {
                let t = zr * zr - zi * zi + cr
                zi = 2 * zr * zi + ci
                zr = t
                n += 1
            }
            iterations += n
        }
        return iterations
    }

    private static func mandelbrot(for seconds: Double) -> Double {
        let start = now()
        var total = 0, row = 0
        while now() - start < seconds {
            for _ in 0..<8 { total += mandelbrotRow(row % 256); row += 1 }
        }
        return Double(total) / (now() - start)
    }

    /// Million iterations per second on one core.
    static func cpuSingleCore(seconds: Double = 2.5) -> Double {
        mandelbrot(for: seconds) / 1e6
    }

    /// Million iterations per second with every core busy.
    static func cpuMultiCore(seconds: Double = 2.5) -> Double {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let rates = UnsafeMutableBufferPointer<Double>.allocate(capacity: cores)
        defer { rates.deallocate() }
        DispatchQueue.concurrentPerform(iterations: cores) { i in rates[i] = mandelbrot(for: seconds) }
        return rates.reduce(0, +) / 1e6
    }

    // MARK: Memory

    /// Multi-threaded copy between two 256 MB buffers. GB/s counts bytes read plus bytes written.
    static func cpuMemoryBandwidth(seconds: Double = 1.5) -> Double {
        let size = 256 << 20
        let src = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16384)
        let dst = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16384)
        defer { src.deallocate(); dst.deallocate() }
        memset(src, 1, size)
        memset(dst, 0, size)

        let threads = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let chunk = size / threads
        var copies = 0
        let start = now()
        while now() - start < seconds {
            DispatchQueue.concurrentPerform(iterations: threads) { i in
                memcpy(dst + i * chunk, src + i * chunk, chunk)
            }
            copies += 1
        }
        let elapsed = now() - start
        return Double(copies * size * 2) / elapsed / 1e9
    }

    // MARK: GPU

    static let matrixSize = 4096

    /// FP16 4096×4096 matrix multiplies through Metal Performance Shaders, timed on the GPU.
    /// Only ever used from one task at a time.
    final class GPUMatmul: @unchecked Sendable {
        let device: MTLDevice
        private let queue: MTLCommandQueue
        private let kernel: MPSMatrixMultiplication
        private let a: MPSMatrix, b: MPSMatrix, c: MPSMatrix
        let n = HardwareBenchmarks.matrixSize

        init?() {
            let n = HardwareBenchmarks.matrixSize
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            self.device = device
            self.queue = queue
            let rowBytes = n * 2
            let descriptor = MPSMatrixDescriptor(rows: n, columns: n, rowBytes: rowBytes, dataType: .float16)
            func matrix() -> MPSMatrix? {
                guard let buffer = device.makeBuffer(length: n * rowBytes, options: .storageModeShared) else { return nil }
                // 0x2000 is 2^-7 in FP16: small, finite, never denormal.
                let values = buffer.contents().bindMemory(to: UInt16.self, capacity: n * n)
                for i in 0..<(n * n) { values[i] = 0x2000 }
                return MPSMatrix(buffer: buffer, descriptor: descriptor)
            }
            guard let a = matrix(), let b = matrix(), let c = matrix() else { return nil }
            self.a = a; self.b = b; self.c = c
            kernel = MPSMatrixMultiplication(device: device, transposeLeft: false, transposeRight: false,
                                             resultRows: n, resultColumns: n, interiorColumns: n, alpha: 1, beta: 0)
        }

        /// Runs `count` multiplies in one command buffer and returns TFLOPS.
        func run(count: Int) -> Double? {
            guard let commands = queue.makeCommandBuffer() else { return nil }
            for _ in 0..<count { kernel.encode(commandBuffer: commands, leftMatrix: a, rightMatrix: b, resultMatrix: c) }
            commands.commit()
            commands.waitUntilCompleted()
            let gpuSeconds = commands.gpuEndTime - commands.gpuStartTime
            guard commands.status == .completed, gpuSeconds > 0 else { return nil }
            return 2 * pow(Double(n), 3) * Double(count) / gpuSeconds / 1e12
        }
    }

    /// Best of a few batches, after a warm-up.
    static func gpuCompute(_ matmul: GPUMatmul) -> Double? {
        _ = matmul.run(count: 2)
        return (0..<4).compactMap { _ in matmul.run(count: 6) }.max()
    }

    /// GPU blit copies between two private 512 MB buffers. GB/s counts bytes read plus bytes written.
    static func gpuMemoryBandwidth(device: MTLDevice) -> Double? {
        let size = 512 << 20
        guard let queue = device.makeCommandQueue(),
              let src = device.makeBuffer(length: size, options: .storageModePrivate),
              let dst = device.makeBuffer(length: size, options: .storageModePrivate) else { return nil }
        func copy(_ count: Int) -> Double? {
            guard let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else { return nil }
            for _ in 0..<count { blit.copy(from: src, sourceOffset: 0, to: dst, destinationOffset: 0, size: size) }
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            let seconds = commands.gpuEndTime - commands.gpuStartTime
            guard commands.status == .completed, seconds > 0 else { return nil }
            return Double(size * 2 * count) / seconds / 1e9
        }
        _ = copy(2)
        return (0..<3).compactMap { _ in copy(8) }.max()
    }

    // MARK: Disk

    /// Writes then reads a 1 GB file with the page cache bypassed (F_NOCACHE), then deletes it.
    static func disk() -> (read: Double?, write: Double?) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-disk-test-\(UUID().uuidString)")
        defer { unlink(url.path) }
        let chunk = 8 << 20, total = 1 << 30
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16384)
        defer { buffer.deallocate() }
        arc4random_buf(buffer, chunk)

        var write: Double?
        let wfd = open(url.path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        if wfd >= 0 {
            _ = fcntl(wfd, F_NOCACHE, 1)
            let start = now()
            var written = 0
            while written < total {
                let n = Darwin.write(wfd, buffer, chunk)
                if n <= 0 { break }
                written += n
            }
            _ = fcntl(wfd, F_FULLFSYNC)
            let elapsed = now() - start
            close(wfd)
            if written == total { write = Double(total) / elapsed / 1e9 }
        }

        var read: Double?
        let rfd = open(url.path, O_RDONLY)
        if rfd >= 0 {
            _ = fcntl(rfd, F_NOCACHE, 1)
            let start = now()
            var got = 0
            while true {
                let n = Darwin.read(rfd, buffer, chunk)
                if n <= 0 { break }
                got += n
            }
            let elapsed = now() - start
            close(rfd)
            if got == total { read = Double(total) / elapsed / 1e9 }
        }
        return (read, write)
    }
}

/// Rough generation speed a model can reach on this Mac: each new token reads every weight once,
/// so memory bandwidth divided by model size sets the ceiling.
enum SpeedEstimate {
    /// The copy figure counts reads and writes while generation mostly reads, which roughly cancels
    /// the overheads. Calibrated on an M4 with Qwen3 4B and 8B (Q4_K_M) in Ollama: within ~10 %.
    static let efficiency = 1.0

    static func tokensPerSecond(modelBytes: Int64, bandwidthGBs: Double) -> Double {
        bandwidthGBs * 1e9 * efficiency / Double(max(modelBytes, 1))
    }
}
