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
              update_signature.swift sign <私钥文件> <安装包> [签名文件] [--version <ver>] [--asset-name <name>]
              update_signature.swift verify <公钥 Base64> <安装包> <签名文件> [--version <ver>] [--asset-name <name>]

            签名内容默认支持 Canonical 绑定（版本+文件名+文件摘要）与原始 SHA-256 双模兼容。
            """
        case .invalidKey(let message):
            return "密钥无效: \(message)"
        case .keyExists(let path):
            return "密钥已存在，未覆盖: \(path)"
        }
    }

    var errorDescription: String? { description }
}

func canonicalPayload(version: String, assetName: String, fileDigest: Data) -> Data {
    let hexDigest = fileDigest.map { String(format: "%02x", $0) }.joined()
    let canonicalString = "ATools-Update:\(version):\(assetName):\(hexDigest)"
    return Data(SHA256.hash(data: Data(canonicalString.utf8)))
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
        var positional: [String] = []
        var version: String?
        var assetName: String?
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--version" && i + 1 < arguments.count {
                version = arguments[i + 1]
                i += 2
            } else if arg == "--asset-name" && i + 1 < arguments.count {
                assetName = arguments[i + 1]
                i += 2
            } else {
                positional.append(arg)
                i += 1
            }
        }
        guard positional.count == 2 || positional.count == 3 else { throw UpdateSignatureError.usage }
        let key = try privateKey(at: positional[0])
        let filePath = positional[1]
        let rawDigest = try sha256(ofFileAt: filePath)
        let resolvedAssetName = assetName ?? URL(fileURLWithPath: filePath).lastPathComponent
        let digest: Data
        if let ver = version, !ver.isEmpty {
            digest = canonicalPayload(version: ver, assetName: resolvedAssetName, fileDigest: rawDigest)
        } else {
            digest = rawDigest
        }
        let signature = try key.signature(for: digest)
        let output = positional.count == 3 ? positional[2] : filePath + ".sig"
        try writeBase64(signature, to: output)
        print(output)

    case "verify":
        var positional: [String] = []
        var version: String?
        var assetName: String?
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--version" && i + 1 < arguments.count {
                version = arguments[i + 1]
                i += 2
            } else if arg == "--asset-name" && i + 1 < arguments.count {
                assetName = arguments[i + 1]
                i += 2
            } else {
                positional.append(arg)
                i += 1
            }
        }
        guard positional.count == 3 else { throw UpdateSignatureError.usage }
        let key = try publicKey(from: positional[0])
        let filePath = positional[1]
        let rawDigest = try sha256(ofFileAt: filePath)
        let signature = try readBase64Line(at: positional[2])
        let resolvedAssetName = assetName ?? URL(fileURLWithPath: filePath).lastPathComponent

        // 双模验证：若提供了 version，先验 Canonical 摘要，回退验 rawDigest
        var verified = false
        if let ver = version, !ver.isEmpty {
            let canon = canonicalPayload(version: ver, assetName: resolvedAssetName, fileDigest: rawDigest)
            if key.isValidSignature(signature, for: canon) {
                verified = true
            }
        }
        if !verified && key.isValidSignature(signature, for: rawDigest) {
            verified = true
        }
        guard verified else {
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
