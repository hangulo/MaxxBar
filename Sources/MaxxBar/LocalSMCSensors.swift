import Foundation
import IOKit

/// Small read-only AppleSMC client. No fan-control or sensor-write operations are exposed.
/// Protocol reference: https://github.com/exelban/stats/blob/master/SMC/smc.swift
final class LocalSMCSensors {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }
    deinit { IOServiceClose(connection) }

    func number(_ key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }
        var request = [UInt8](repeating: 0, count: 80)
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        withUnsafeBytes(of: code) { request.replaceSubrange(0..<4, with: $0) }
        request[42] = 9 // Key metadata.
        guard let metadata = transact(request) else { return nil }
        let length = metadata.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt32.self) }
        let type = metadata.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self) }
        guard length > 0, length <= 32 else { return nil }
        request.replaceSubrange(28..<32, with: metadata[28..<32])
        request[42] = 5 // Read bytes.
        guard let response = transact(request) else { return nil }
        return Self.decode(type: type, bytes: Array(response[48..<(48 + Int(length))]))
    }

    private func transact(_ request: [UInt8]) -> [UInt8]? {
        var response = [UInt8](repeating: 0, count: 80)
        var length = response.count
        let result = request.withUnsafeBytes { input in
            response.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(connection, 2, input.baseAddress, input.count, output.baseAddress, &length)
            }
        }
        guard result == KERN_SUCCESS, length == 80, response[40] == 0 else { return nil }
        return response
    }

    static func decode(type: UInt32, bytes: [UInt8]) -> Double? {
        let value: Double
        switch type {
        case 0x666c7420: // flt : native floating point on Apple Silicon.
            guard bytes.count == 4 else { return nil }
            value = Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case 0x66706532: // fpe2: unsigned fixed point, two fraction bits.
            guard bytes.count == 2 else { return nil }
            value = Double(UInt16(bytes[0]) * 256 + UInt16(bytes[1])) / 4
        case 0x73703738: // sp78: signed fixed point, eight fraction bits.
            guard bytes.count == 2 else { return nil }
            value = Double(Int16(bitPattern: UInt16(bytes[0]) * 256 + UInt16(bytes[1]))) / 256
        case 0x75693820: // ui8
            guard bytes.count == 1 else { return nil }
            value = Double(bytes[0])
        case 0x75693136: // ui16
            guard bytes.count == 2 else { return nil }
            value = Double(UInt16(bytes[0]) * 256 + UInt16(bytes[1]))
        default: return nil
        }
        return value.isFinite ? value : nil
    }

    var fanSpeeds: [Int] {
        guard let count = number("FNum"), count >= 0, count <= 8 else { return [] }
        return (0..<Int(count)).compactMap { index in
            guard let value = number("F\(index)Ac"), (0..<10_000).contains(value) else { return nil }
            return Int(value.rounded())
        }
    }

    var cpuTemperature: Double? {
        maximumTemperature(keys: ["TC0P", "TC0D", "Tp01", "Tp05", "Tp09", "Tp0D", "Te05", "Te0S", "Te09", "Te0H", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tp0O", "Tp0R", "Tp0U"])
    }
    var gpuTemperature: Double? {
        maximumTemperature(keys: ["TG0P", "TG0D", "Tg0f", "Tg0j", "Tg05", "Tg0D", "Tf14", "Tf18"])
    }
    private func maximumTemperature(keys: [String]) -> Double? {
        keys.compactMap(number).filter { $0 > 0 && $0 < 130 }.max()
    }
}
