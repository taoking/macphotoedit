import Foundation
import MachO

enum SimilarPhotoPerformanceInstrumentation {
    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func observePeak(_ peak: inout UInt64?) {
        guard let resident = residentMemoryBytes() else { return }
        peak = max(peak ?? 0, resident)
    }

    /// A lightweight sampled resident-set measurement. It is not a profiler's
    /// allocation high-water mark, so reports name it "observed" rather than
    /// claiming exact peak memory. If the OS declines task_info, callers keep
    /// `nil` and do not invent a memory figure.
    static func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
}
