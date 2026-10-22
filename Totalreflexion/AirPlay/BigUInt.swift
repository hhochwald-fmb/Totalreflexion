import Foundation

/// Unsigned big integer with just the arithmetic SRP needs. Fast modular arithmetic lives in
/// `MontgomeryModulus`; the operators here are simple and only used on a few values per pairing.
struct BigUInt: Comparable {
    /// Little-endian 64-bit limbs without leading zero limbs; zero is empty.
    private(set) var limbs: [UInt64]

    init(limbs: [UInt64]) {
        self.limbs = limbs
        while self.limbs.last == 0 {
            self.limbs.removeLast()
        }
    }

    init(_ value: UInt64) {
        self.init(limbs: [value])
    }

    /// From big-endian bytes.
    init(_ bytes: Data) {
        var limbs: [UInt64] = []
        var limb: UInt64 = 0
        var shift: UInt64 = 0
        for byte in bytes.reversed() {
            limb |= UInt64(byte) << shift
            shift += 8
            if shift == 64 {
                limbs.append(limb)
                limb = 0
                shift = 0
            }
        }
        if shift > 0 {
            limbs.append(limb)
        }
        self.init(limbs: limbs)
    }

    init(hex: String) {
        var bytes = Data()
        var digits = Array(hex.filter(\.isHexDigit))
        if digits.count % 2 == 1 {
            digits.insert("0", at: 0)
        }
        for index in stride(from: 0, to: digits.count, by: 2) {
            bytes.append(UInt8(String(digits[index...index + 1]), radix: 16) ?? 0)
        }
        self.init(bytes)
    }

    var isZero: Bool { limbs.isEmpty }

    /// Big-endian bytes without leading zeros, like OpenSSL's BN_bn2bin (the client hashes exactly these).
    var bytes: Data {
        var result = Data()
        for limb in limbs.reversed() {
            for shift in stride(from: 56, through: 0, by: -8) {
                result.append(UInt8(truncatingIfNeeded: limb >> UInt64(shift)))
            }
        }
        return Data(result.drop { $0 == 0 })
    }

    /// Big-endian bytes, left-padded with zeros to `length`.
    func padded(to length: Int) -> Data {
        let value = bytes
        return Data(count: max(0, length - value.count)) + value
    }

    var bitWidth: Int {
        guard let top = limbs.last else { return 0 }
        return limbs.count * 64 - top.leadingZeroBitCount
    }

    func bit(_ index: Int) -> Bool {
        (limbs[index / 64] >> UInt64(index % 64)) & 1 == 1
    }

    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        compare(lhs.limbs, rhs.limbs) < 0
    }

    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        var result: [UInt64] = []
        var carry = false
        for index in 0..<max(lhs.limbs.count, rhs.limbs.count) {
            let left = index < lhs.limbs.count ? lhs.limbs[index] : 0
            let right = index < rhs.limbs.count ? rhs.limbs[index] : 0
            let (sum, overflow1) = left.addingReportingOverflow(right)
            let (total, overflow2) = sum.addingReportingOverflow(carry ? 1 : 0)
            result.append(total)
            carry = overflow1 || overflow2
        }
        if carry {
            result.append(1)
        }
        return BigUInt(limbs: result)
    }

    /// Requires lhs >= rhs.
    static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        var padded = rhs.limbs
        padded += [UInt64](repeating: 0, count: max(0, lhs.limbs.count - padded.count))
        return BigUInt(limbs: subtract(lhs.limbs, padded))
    }

    static func -= (lhs: inout BigUInt, rhs: BigUInt) {
        lhs = lhs - rhs
    }

    static func % (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        precondition(!rhs.isZero, "modulo zero")
        guard lhs >= rhs else { return lhs }
        // Bitwise long division: only used for a handful of reductions per pairing.
        var remainder = BigUInt(limbs: [])
        for index in stride(from: lhs.bitWidth - 1, through: 0, by: -1) {
            remainder = remainder.shiftedLeftByOne(insertingBit: lhs.bit(index))
            if remainder >= rhs {
                remainder -= rhs
            }
        }
        return remainder
    }

    private func shiftedLeftByOne(insertingBit bit: Bool) -> BigUInt {
        var result: [UInt64] = []
        result.reserveCapacity(limbs.count + 1)
        var carry: UInt64 = bit ? 1 : 0
        for limb in limbs {
            result.append(limb << 1 | carry)
            carry = limb >> 63
        }
        if carry != 0 {
            result.append(carry)
        }
        return BigUInt(limbs: result)
    }

    /// Compares limb arrays of possibly different length.
    static func compare(_ lhs: [UInt64], _ rhs: [UInt64]) -> Int {
        let count = max(lhs.count, rhs.count)
        for index in stride(from: count - 1, through: 0, by: -1) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }
        return 0
    }

    /// lhs - rhs on equally long arrays, wrapping on underflow.
    static func subtract(_ lhs: [UInt64], _ rhs: [UInt64]) -> [UInt64] {
        var result = lhs
        var borrow = false
        for index in 0..<lhs.count {
            let (difference, underflow1) = lhs[index].subtractingReportingOverflow(rhs[index])
            let (total, underflow2) = difference.subtractingReportingOverflow(borrow ? 1 : 0)
            result[index] = total
            borrow = underflow1 || underflow2
        }
        return result
    }
}

/// Arithmetic modulo a fixed odd modulus, with exponentiation in Montgomery form.
struct MontgomeryModulus {
    let modulus: BigUInt
    private let limbs: [UInt64]
    private let count: Int
    /// -modulus⁻¹ mod 2⁶⁴.
    private let inverse: UInt64
    /// R² mod modulus with R = 2^(64·count), to move numbers into Montgomery form.
    private let rSquared: [UInt64]

    init(_ modulus: BigUInt) {
        precondition(modulus.limbs.first.map { $0 & 1 == 1 } ?? false, "Montgomery needs an odd modulus")
        self.modulus = modulus
        limbs = modulus.limbs
        count = limbs.count
        // Newton iteration doubles the correct bits each round: 1 → 64 bits in six rounds.
        var value: UInt64 = 1
        for _ in 0..<6 {
            value = value &* (2 &- limbs[0] &* value)
        }
        inverse = 0 &- value
        let rToTheFourth = BigUInt(limbs: [UInt64](repeating: 0, count: 2 * count) + [1])
        rSquared = Self.pad((rToTheFourth % modulus).limbs, to: count)
    }

    func multiply(_ lhs: BigUInt, _ rhs: BigUInt) -> BigUInt {
        let product = montgomeryProduct(reduced(lhs), reduced(rhs))
        return BigUInt(limbs: montgomeryProduct(product, rSquared))
    }

    func add(_ lhs: BigUInt, _ rhs: BigUInt) -> BigUInt {
        let sum = (lhs % modulus) + (rhs % modulus)
        return sum >= modulus ? sum - modulus : sum
    }

    func power(_ base: BigUInt, _ exponent: BigUInt) -> BigUInt {
        let one = Self.pad([1], to: count)
        let factor = montgomeryProduct(reduced(base), rSquared)
        var result = montgomeryProduct(one, rSquared)
        for index in stride(from: exponent.bitWidth - 1, through: 0, by: -1) {
            result = montgomeryProduct(result, result)
            if exponent.bit(index) {
                result = montgomeryProduct(result, factor)
            }
        }
        return BigUInt(limbs: montgomeryProduct(result, one))
    }

    private func reduced(_ value: BigUInt) -> [UInt64] {
        Self.pad((value % modulus).limbs, to: count)
    }

    /// a · b · R⁻¹ mod modulus (CIOS method); inputs and output are `count` limbs and below the modulus.
    private func montgomeryProduct(_ lhs: [UInt64], _ rhs: [UInt64]) -> [UInt64] {
        var acc = [UInt64](repeating: 0, count: count + 2)
        for outer in 0..<count {
            var carry: UInt64 = 0
            for inner in 0..<count {
                let (high, low) = Self.multiplyAdd(lhs[inner], rhs[outer], acc[inner], carry)
                acc[inner] = low
                carry = high
            }
            let (top, topOverflow) = acc[count].addingReportingOverflow(carry)
            acc[count] = top
            acc[count + 1] = topOverflow ? 1 : 0

            let factor = acc[0] &* inverse
            carry = Self.multiplyAdd(factor, limbs[0], acc[0], 0).high
            for inner in 1..<count {
                let (high, low) = Self.multiplyAdd(factor, limbs[inner], acc[inner], carry)
                acc[inner - 1] = low
                carry = high
            }
            let (shifted, overflow) = acc[count].addingReportingOverflow(carry)
            acc[count - 1] = shifted
            acc[count] = acc[count + 1] &+ (overflow ? 1 : 0)
            acc[count + 1] = 0
        }
        var result = Array(acc[0..<count])
        if acc[count] != 0 || BigUInt.compare(result, limbs) >= 0 {
            result = BigUInt.subtract(result, limbs)
        }
        return result
    }

    /// a · b + c + d; the result always fits into 128 bits.
    private static func multiplyAdd(_ lhs: UInt64, _ rhs: UInt64, _ addend: UInt64,
                                    _ carry: UInt64) -> (high: UInt64, low: UInt64) {
        let (high, low) = lhs.multipliedFullWidth(by: rhs)
        let (sum, overflow1) = low.addingReportingOverflow(addend)
        let (total, overflow2) = sum.addingReportingOverflow(carry)
        return (high &+ (overflow1 ? 1 : 0) &+ (overflow2 ? 1 : 0), total)
    }

    private static func pad(_ limbs: [UInt64], to count: Int) -> [UInt64] {
        limbs + [UInt64](repeating: 0, count: max(0, count - limbs.count))
    }
}
