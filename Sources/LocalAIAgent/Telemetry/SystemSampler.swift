import Darwin
import Foundation
import IOKit
import SensorsC

struct SystemSnapshot {
    var timestamp = Date()

    var cpuUsage: Double?
    var perCoreUsage: [Double] = []

    var gpuUsage: Double?
    var gpuMemoryInUse: Int64?

    var memoryTotal: Int64 = 0
    var memoryUsed: Int64 = 0
    var memoryApp: Int64 = 0
    var memoryWired: Int64 = 0
    var memoryCompressed: Int64 = 0
    var swapUsed: Int64 = 0
    /// Kernel memory-pressure level: 1 = normal, 2 = warning, 4 = critical.
    var memoryPressure: Int = 1

    var cpuTemp: Double?
    var cpuTempMax: Double?
    var gpuTemp: Double?
    var gpuTempMax: Double?
    var memoryTemp: Double?
    var socTemp: Double?
    var thermalState: ProcessInfo.ThermalState = .nominal

    var memoryPercent: Double? { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) * 100 : nil }

    var memoryLevel: HealthLevel {
        let usage = Thresholds.memoryUsage.level(memoryPercent)
        let pressure: HealthLevel = memoryPressure >= 4 ? .critical : (memoryPressure >= 2 ? .warning : .good)
        return max(usage == .unknown ? .good : usage, pressure)
    }
}

/// Reads CPU, GPU, memory and temperature data. Not thread-safe: drive it from one task at a time.
final class SystemSampler: @unchecked Sendable {
    private var previousTicks: [[UInt32]] = []
    private var smcCPUKeys: [String] = []
    private var smcGPUKeys: [String] = []
    private var smcMemoryKeys: [String] = []
    private var didEnumerateSMC = false
    private var lastThermals = SystemSnapshot()

    func sample(includeThermals: Bool) -> SystemSnapshot {
        var s = SystemSnapshot()
        sampleCPU(into: &s)
        sampleGPU(into: &s)
        sampleMemory(into: &s)
        if includeThermals {
            sampleThermals(into: &s)
            lastThermals = s
        } else {
            s.cpuTemp = lastThermals.cpuTemp
            s.cpuTempMax = lastThermals.cpuTempMax
            s.gpuTemp = lastThermals.gpuTemp
            s.gpuTempMax = lastThermals.gpuTempMax
            s.memoryTemp = lastThermals.memoryTemp
            s.socTemp = lastThermals.socTemp
        }
        s.thermalState = ProcessInfo.processInfo.thermalState
        return s
    }

    // MARK: CPU

    private func sampleCPU(into s: inout SystemSnapshot) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        for cpu in 0..<Int(cpuCount) {
            ticks.append((0..<states).map { UInt32(bitPattern: info[cpu * states + $0]) })
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return }

        var totalBusy: UInt64 = 0, totalAll: UInt64 = 0
        var perCore: [Double] = []
        for (now, before) in zip(ticks, previousTicks) {
            let d = (0..<states).map { UInt64(now[$0] &- before[$0]) }
            let user = d[Int(CPU_STATE_USER)], sys = d[Int(CPU_STATE_SYSTEM)]
            let idle = d[Int(CPU_STATE_IDLE)], nice = d[Int(CPU_STATE_NICE)]
            let busy = user + sys + nice, all = busy + idle
            totalBusy += busy; totalAll += all
            perCore.append(all > 0 ? Double(busy) / Double(all) * 100 : 0)
        }
        s.cpuUsage = totalAll > 0 ? Double(totalBusy) / Double(totalAll) * 100 : nil
        s.perCoreUsage = perCore
    }

    // MARK: GPU

    private func sampleGPU(into s: inout SystemSnapshot) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            guard let raw = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let stats = raw.takeRetainedValue() as? [String: Any] else { continue }
            if let util = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                s.gpuUsage = max(s.gpuUsage ?? 0, util)
            }
            if let mem = (stats["In use system memory"] as? NSNumber)?.int64Value {
                s.gpuMemoryInUse = (s.gpuMemoryInUse ?? 0) + mem
            }
        }
    }

    // MARK: Memory

    private func sampleMemory(into s: inout SystemSnapshot) {
        s.memoryTotal = Int64(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            // Matches Activity Monitor: App Memory + Wired + Compressed.
            s.memoryApp = (Int64(stats.internal_page_count) - Int64(stats.purgeable_count)) * page
            s.memoryWired = Int64(stats.wire_count) * page
            s.memoryCompressed = Int64(stats.compressor_page_count) * page
            s.memoryUsed = s.memoryApp + s.memoryWired + s.memoryCompressed
        }

        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            s.memoryPressure = Int(level)
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            s.swapUsed = Int64(swap.xsu_used)
        }
    }

    // MARK: Temperatures

    private func enumerateSMC() {
        didEnumerateSMC = true
        let maxKeys = 1024
        var buffer = [CChar](repeating: 0, count: maxKeys * 5)
        let n = Int(sensors_smc_temperature_keys(&buffer, Int32(maxKeys)))
        var keys: [String] = []
        for i in 0..<n {
            let key = buffer[(i * 5)..<(i * 5 + 4)].map { Character(UnicodeScalar(UInt8(bitPattern: $0))) }
            keys.append(String(key))
        }
        // Apple Silicon naming: Tp* = performance cores, Te* = efficiency cores, Tg* = GPU, Tm* = memory.
        smcCPUKeys = keys.filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
        smcGPUKeys = keys.filter { $0.hasPrefix("Tg") }
        smcMemoryKeys = keys.filter { $0.hasPrefix("Tm") }
        // Intel Macs: TC0P/TC0D etc. for CPU, TG0P for GPU.
        if smcCPUKeys.isEmpty { smcCPUKeys = keys.filter { $0.hasPrefix("TC") } }
        if smcGPUKeys.isEmpty { smcGPUKeys = keys.filter { $0.hasPrefix("TG") } }
    }

    private func readSMC(_ keys: [String]) -> [Double] {
        keys.compactMap { key in
            let v = sensors_smc_read(key)
            return (10...130).contains(v) ? v : nil
        }
    }

    private func sampleThermals(into s: inout SystemSnapshot) {
        if !didEnumerateSMC { enumerateSMC() }

        let cpu = readSMC(smcCPUKeys)
        let gpu = readSMC(smcGPUKeys)
        let mem = readSMC(smcMemoryKeys)

        // HID sensors: SoC die temperatures, plus fallbacks when SMC keys are missing.
        let maxSensors = 128
        var names = [CChar](repeating: 0, count: maxSensors * 64)
        var values = [Double](repeating: 0, count: maxSensors)
        let n = Int(sensors_hid_temperatures(&names, &values, Int32(maxSensors)))
        var hidCPU: [Double] = [], hidGPU: [Double] = [], hidSoC: [Double] = []
        for i in 0..<n {
            let name = names.withUnsafeBufferPointer { String(cString: $0.baseAddress! + i * 64) }
            let v = values[i]
            guard (10...130).contains(v) else { continue }
            if name.contains("tdie") { hidSoC.append(v) }
            if name.hasPrefix("pACC") || name.hasPrefix("eACC") { hidCPU.append(v) }
            if name.hasPrefix("GPU") { hidGPU.append(v) }
        }

        let cpuValues = cpu.isEmpty ? (hidCPU.isEmpty ? hidSoC : hidCPU) : cpu
        s.cpuTemp = average(cpuValues)
        s.cpuTempMax = cpuValues.max()
        let gpuValues = gpu.isEmpty ? hidGPU : gpu
        s.gpuTemp = average(gpuValues)
        s.gpuTempMax = gpuValues.max()
        s.memoryTemp = average(mem)
        s.socTemp = average(hidSoC)
    }

    private func average(_ v: [Double]) -> Double? {
        v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}
