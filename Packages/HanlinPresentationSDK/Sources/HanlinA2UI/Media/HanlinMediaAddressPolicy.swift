/// Media requests use conservative internet destination admission. Special-use
/// ranges follow IANA's IPv4/IPv6 registries; mapped/NAT64 addresses must also
/// carry an admitted IPv4 destination. DNS preflight does not pin URLSession DNS.
public enum HanlinMediaAddressPolicy {
    public static func publicIPv4(_ ip: UInt32) -> Bool {
        let a = ip >> 24, b = (ip >> 16) & 255, c = (ip >> 8) & 255
        return a != 0 && a != 10 && a != 127 && a < 224
            && !(a == 100 && (64...127).contains(b))
            && !(a == 169 && b == 254) && !(a == 172 && (16...31).contains(b))
            && !(a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2))))
            && !(a == 192 && b == 88 && c == 99)
            && !(a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100)))
            && !(a == 203 && b == 0 && c == 113)
    }

    public static func publicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        let mapped = bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255
        let nat64 = bytes[0...3] == [0, 0x64, 0xff, 0x9b] && bytes[4..<12].allSatisfy({ $0 == 0 })
        if mapped || nat64 {
            return publicIPv4(bytes.suffix(4).reduce(0) { ($0 << 8) | UInt32($1) })
        }
        // Only global unicast, excluding documentation and transition/special ranges.
        return bytes[0] & 0xe0 == 0x20
            && !(bytes[0] == 0x20 && bytes[1] == 0x02)
            && !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] <= 1)
            && !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8)
            && !(bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] & 0xf0 == 0)
    }
}
