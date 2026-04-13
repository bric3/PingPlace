import Darwin
import Foundation

enum MachineModelPolicy {
    static func isPortableMac(modelIdentifier: String) -> Bool {
        modelIdentifier.hasPrefix("MacBook")
    }

    static func currentModelIdentifier() -> String? {
        var size: size_t = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }
}
