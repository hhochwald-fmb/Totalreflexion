import CommonCrypto
import CryptoKit
import Foundation

enum Crypto {
    static func sha512(_ parts: Data...) -> Data {
        var hasher = SHA512()
        for part in parts {
            hasher.update(data: part)
        }
        return Data(hasher.finalize())
    }

    /// Encrypts full 16-byte blocks with AES-128-ECB (no padding). Building block for CTR mode.
    static func aesECBEncrypt(key: Data, blocks: Data) -> Data {
        var output = Data(count: blocks.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            blocks.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            keyBytes.baseAddress, key.count, nil,
                            input.baseAddress, blocks.count,
                            out.baseAddress, blocks.count, &moved)
                }
            }
        }
        return status == kCCSuccess ? output : Data(count: blocks.count)
    }

    /// AES-128-CBC decryption of whole blocks without padding.
    static func aesCBCDecrypt(key: Data, iv: Data, data: Data) -> Data {
        var output = Data(count: data.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                input.baseAddress, data.count,
                                out.baseAddress, data.count, &moved)
                    }
                }
            }
        }
        return status == kCCSuccess ? output : data
    }
}

/// AES-128 in counter mode with a 128-bit big-endian counter (OpenSSL semantics).
/// The keystream continues across calls, which the mirroring stream relies on.
final class AESCTR {
    private let key: Data
    private var counter: [UInt8]
    private var keystream = [UInt8]()
    private var keystreamOffset = 0

    init(key: Data, iv: Data) {
        self.key = key.prefix(16)
        counter = Array(iv.prefix(16))
    }

    func process(_ input: Data) -> Data {
        var output = [UInt8](input)
        var index = 0
        while index < output.count {
            if keystreamOffset >= keystream.count {
                refill(byteCount: output.count - index)
            }
            let available = min(keystream.count - keystreamOffset, output.count - index)
            for offset in 0..<available {
                output[index + offset] ^= keystream[keystreamOffset + offset]
            }
            index += available
            keystreamOffset += available
        }
        return Data(output)
    }

    private func refill(byteCount: Int) {
        let blockCount = max(1, (byteCount + 15) / 16)
        var counterBlocks = [UInt8]()
        counterBlocks.reserveCapacity(blockCount * 16)
        for _ in 0..<blockCount {
            counterBlocks.append(contentsOf: counter)
            incrementCounter()
        }
        keystream = [UInt8](Crypto.aesECBEncrypt(key: key, blocks: Data(counterBlocks)))
        keystreamOffset = 0
    }

    private func incrementCounter() {
        for position in stride(from: 15, through: 0, by: -1) {
            counter[position] &+= 1
            if counter[position] != 0 {
                break
            }
        }
    }
}
