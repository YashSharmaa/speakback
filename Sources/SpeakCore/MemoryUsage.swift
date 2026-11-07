import Darwin

/// This process's memory: physical footprint (what Activity Monitor shows) and resident size.
public enum MemoryUsage {
    public static func current() -> (footprintMB: Double, residentMB: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        let mb = 1024.0 * 1024.0
        return (Double(info.phys_footprint) / mb, Double(info.resident_size) / mb)
    }
}
