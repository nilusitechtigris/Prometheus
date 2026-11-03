import Foundation
import IOKit
import Metal
import Observation

struct SamplePoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
}

/// A fixed-size rolling history for sparklines.
struct Series {
    private(set) var points: [SamplePoint] = []
    private var counter = 0
    let capacity: Int

    init(capacity: Int = 120) { self.capacity = capacity }

    mutating func append(_ value: Double?, at date: Date) {
        guard let value, value.isFinite else { return }
        counter += 1
        points.append(SamplePoint(id: counter, date: date, value: value))
        if points.count > capacity { points.removeFirst(points.count - capacity) }
    }
}

@MainActor
@Observable
final class SystemMonitor {
    private(set) var snapshot = SystemSnapshot()
    private(set) var cpu = Series()
    private(set) var gpu = Series()
    private(set) var memory = Series()
    private(set) var cpuTemp = Series()
    private(set) var gpuTemp = Series()
    private(set) var memoryTemp = Series()

    let chipName: String
    let gpuCoreCount: Int?
    /// Memory macOS lets the GPU wire for model weights (Metal's recommended working set).
    let gpuBudgetBytes: Int64

    private let sampler = SystemSampler()
    private var task: Task<Void, Never>?

    init() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        chipName = String(cString: buf)

        let device = MTLCreateSystemDefaultDevice()
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        gpuBudgetBytes = Int64(device?.recommendedMaxWorkingSetSize ?? UInt64(Double(physical) * 0.66))
        gpuCoreCount = Self.readGPUCoreCount()
    }

    func start() {
        guard task == nil else { return }
        let sampler = self.sampler
        task = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                let includeThermals = tick % 2 == 0
                let snap = await Task.detached(priority: .utility) {
                    sampler.sample(includeThermals: includeThermals)
                }.value
                self?.apply(snap)
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func apply(_ s: SystemSnapshot) {
        snapshot = s
        cpu.append(s.cpuUsage, at: s.timestamp)
        gpu.append(s.gpuUsage, at: s.timestamp)
        memory.append(s.memoryPercent, at: s.timestamp)
        cpuTemp.append(s.cpuTemp, at: s.timestamp)
        gpuTemp.append(s.gpuTemp, at: s.timestamp)
        memoryTemp.append(s.memoryTemp, at: s.timestamp)
    }

    var worstLevel: HealthLevel {
        let s = snapshot
        let levels = [
            Thresholds.cpuUsage.level(s.cpuUsage),
            Thresholds.gpuUsage.level(s.gpuUsage),
            s.memoryLevel,
            Thresholds.cpuTemp.level(s.cpuTemp),
            Thresholds.gpuTemp.level(s.gpuTemp),
            Thresholds.memoryTemp.level(s.memoryTemp),
        ].filter { $0 != .unknown }
        return levels.max() ?? .unknown
    }

    private static func readGPUCoreCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }
}
