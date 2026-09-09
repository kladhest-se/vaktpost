import XCTest
@testable import Vaktpost

final class MacVendorDatabaseTests: XCTestCase {
    func testLongestRegisteredPrefixWins() throws {
        let index = try MacVendorIndex(data: fixture())
        XCTAssertEqual(index.lookup(mac: "00:11:22:33:44:55"),
                       .found(vendor: "Small Devices", prefix: "00:11:22:33:4", registry: "MA-S"))
        XCTAssertEqual(index.lookup(mac: "00:11:22:3F:44:55"),
                       .found(vendor: "Medium Devices", prefix: "00:11:22:3", registry: "MA-M"))
        XCTAssertEqual(index.lookup(mac: "00:11:22:FF:44:55"),
                       .found(vendor: "Large Devices", prefix: "00:11:22", registry: "MA-L"))
    }

    func testLocalMulticastUnknownAndInvalidAddresses() throws {
        let index = try MacVendorIndex(data: fixture())
        XCTAssertEqual(index.lookup(mac: "02:11:22:33:44:55"), .locallyAdministered)
        XCTAssertEqual(index.lookup(mac: "01:00:5E:00:00:01"), .multicast)
        XCTAssertEqual(index.lookup(mac: "00:AA:BB:CC:DD:EE"), .unknown)
        XCTAssertEqual(index.lookup(mac: "—"), .invalid)
    }

    func testCorruptDatabaseIsRejected() {
        XCTAssertThrowsError(try MacVendorIndex(data: Data("not a database".utf8)))
    }

    private func fixture() -> Data {
        let vendors = Data("Large Devices\0Medium Devices\0Small Devices\0".utf8)
        var data = Data("VKIEEE01".utf8)
        append(UInt32(3), to: &data)
        append(UInt32(vendors.count), to: &data)
        append(bits: 24, prefix: 0x001122, offset: 0, registry: 0, to: &data)
        append(bits: 28, prefix: 0x0011223, offset: 14, registry: 1, to: &data)
        append(bits: 36, prefix: 0x001122334, offset: 29, registry: 2, to: &data)
        data.append(vendors)
        return data
    }

    private func append(bits: UInt8, prefix: UInt64, offset: UInt32,
                        registry: UInt8, to data: inout Data) {
        data.append(bits)
        append(prefix, to: &data)
        append(offset, to: &data)
        data.append(registry)
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
