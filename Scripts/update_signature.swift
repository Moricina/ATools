#!/usr/bin/env swift

import CryptoKit
import Foundation

enum UpdateSignatureError: Error, CustomStringConvertible, LocalizedError {
    case usage
    case invalidKey(String)
    case keyExists(String)

    var description: String {
        switch self {
        case .usage:
            return """
            用法:
              update_signature.swift keygen <私钥文件>
              update_signature.swift public-key <私钥文件>
              update_signature.swift sign <私钥文件> <安装包> [签名文件]
              update_signature.swift verify <公钥 Base64> <安装包> <签名文件>

            签名内容为安装包 SHA-256 摘要的 Ed25519 签名，签名文件使用 Base64 文本。
            """
        case .invalidKey(let message):
            return "密钥无效: \(message)"
        case .keyExists(let path):
            return "密钥已存在，未覆盖: \(path)"
        }
    }

    var errorDescription: String? { description }
}

func readBase64Line(at path: String) throws -> Data {
    let value = try String(contentsOfFile: path, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: value) else {
        throw UpdateSignatureError.invalidKey("\(path) 不是有效的 Base64 数据")
    }
    return data
}

func writeBase64(_ data: Data, to path: String) throws {
    try (data.base64EncodedString() + "\n").write(
        toFile: path,
        atomically: true,
        encoding: .utf8
    )
}

func sha256(ofFileAt path: String) throws -> Data {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }

    var hasher = SHA256()
    while true {
        let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
        if chunk.isEmpty { break }
        chunk.withUnsafeBytes { buffer in
            hasher.update(bufferPointer: buffer)
        }
    }
    return Data(hasher.finalize())
}

func privateKey(at path: String) throws -> Curve25519.Signing.PrivateKey {
    do {
        return try Curve25519.Signing.PrivateKey(rawRepresentation: readBase64Line(at: path))
    } catch let error as UpdateSignatureError {
        throw error
    } catch {
        throw UpdateSignatureError.invalidKey(error.localizedDescription)
    }
}

func publicKey(from base64: String) throws -> Curve25519.Signing.PublicKey {
    guard let raw = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw UpdateSignatureError.invalidKey("公钥不是有效的 Base64 数据")
    }
    do {
        return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    } catch {
        throw UpdateSignatureError.invalidKey(error.localizedDescription)
    }
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        throw UpdateSignatureError.usage
    }

    switch command {
    case "keygen":
        guard arguments.count == 2 else { throw UpdateSignatureError.usage }
        let path = arguments[1]
        guard !FileManager.default.fileExists(atPath: path) else {
            throw UpdateSignatureError.keyExists(path)
        }

        let key = Curve25519.Signing.PrivateKey()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeBase64(key.rawRepresentation, to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        print(key.publicKey.rawRepresentation.base64EncodedString())

    case "public-key":
        guard arguments.count == 2 else { throw UpdateSignatureError.usage }
        print(try privateKey(at: arguments[1]).publicKey.rawRepresentation.base64EncodedString())

    case "sign":
        guard arguments.count == 3 || arguments.count == 4 else { throw UpdateSignatureError.usage }
        let key = try privateKey(at: arguments[1])
        let digest = try sha256(ofFileAt: arguments[2])
        let signature = try key.signature(for: digest)
        let output = arguments.count == 4 ? arguments[3] : arguments[2] + ".sig"
        try writeBase64(signature, to: output)
        print(output)

    case "verify":
        guard arguments.count == 4 else { throw UpdateSignatureError.usage }
        let key = try publicKey(from: arguments[1])
        let digest = try sha256(ofFileAt: arguments[2])
        let signature = try readBase64Line(at: arguments[3])
        guard key.isValidSignature(signature, for: digest) else {
            throw UpdateSignatureError.invalidKey("安装包签名校验失败")
        }
        print("OK")

    default:
        throw UpdateSignatureError.usage
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
