import Combine
import Darwin.Mach
import Foundation

class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var diskUsage: Double = 0

    private var timer: Timer?
    private var previousCPUTicks: [UInt64]?
    private static let enabledDefaultsKey = "systemMonitoringEnabled"

    init() {
        if UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)

        if enabled {
            previousCPUTicks = nil
            sample()
            startTimer()
        } else {
            timer?.invalidate()
            timer = nil
            previousCPUTicks = nil
        }
    }

    func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sample()
        }

        if let timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func sampleCPU() {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &loadInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let ticks = withUnsafeBytes(of: loadInfo.cpu_ticks) { rawBuffer in
            rawBuffer.bindMemory(to: UInt32.self).map(UInt64.init)
        }

        guard ticks.count >= CPU_STATE_MAX else { return }
        defer { previousCPUTicks = ticks }

        guard let previousCPUTicks, previousCPUTicks.count == ticks.count else {
            return
        }

        let deltas = zip(ticks, previousCPUTicks).map { current, previous in
            current >= previous ? current - previous : 0
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return }

        let idle = deltas[Int(CPU_STATE_IDLE)]
        cpuUsage = clamped(Double(total - idle) / Double(total))
    }

    private func sampleMemory() {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return }

        // Equivalente à categoria "Memória Usada" do Monitor de Atividade:
        // inclui páginas de apps/sistema, wired e comprimidas, mas não trata
        // arquivos em cache ou memória purgável como consumo real de RAM.
        let occupiedPages = UInt64(statistics.active_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let reclaimablePages = UInt64(statistics.purgeable_count)
            + UInt64(statistics.external_page_count)
        let usedPages = occupiedPages > reclaimablePages
            ? occupiedPages - reclaimablePages
            : 0
        let usedBytes = usedPages * UInt64(vm_kernel_page_size)
        memoryUsage = clamped(Double(usedBytes) / Double(totalBytes))
    }

    private func sampleDisk() {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        ),
        let totalBytes = values.volumeTotalCapacity,
        let availableBytes = values.volumeAvailableCapacity,
        totalBytes > 0 else {
            return
        }

        diskUsage = clamped(
            Double(totalBytes - availableBytes) / Double(totalBytes)
        )
    }

    private func clamped(_ value: Double) -> Double {
        Swift.min(Swift.max(value, 0), 1)
    }
}
