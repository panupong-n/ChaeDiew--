import ChaeDiewLicense
import Foundation
import IOKit

/// The operating system's own identifier for this Mac (the same value the Electron build reads on macOS, so one activation covers both).
enum MachineID {
    static var raw: String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { if service != 0 { IOObjectRelease(service) } }
        if service != 0,
           let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
           !value.isEmpty { return value }
        return ProcessInfo.processInfo.hostName   // very old / virtual hardware without a platform UUID
    }

    static var code: String { MachineBinding.machineCode(rawID: raw) }
}
