#!/usr/bin/env swift
//
//  asc-jwt.swift
//  Prints a short-lived App Store Connect API token.
//
//  usage: asc-jwt.swift <AuthKey.p8> <key-id> <issuer-id> [lifetime-seconds]
//
//  Signing is ES256, which neither `openssl` nor stock Python can do here
//  without extra packages; CryptoKit ships with the OS.

import CryptoKit
import Foundation

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: asc-jwt.swift <key.p8> <key-id> <issuer-id> [lifetime]\n".utf8))
    exit(64)
}
// App Store Connect refuses any token that expires more than 20 minutes out,
// and answers 401 without saying why — so clamp rather than pass it through.
let requested = args.count > 4 ? Int(args[4]) ?? 1200 : 1200
let lifetime = min(max(requested, 60), 1200)

do {
    let pem = try String(contentsOfFile: args[1], encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let now = Int(Date().timeIntervalSince1970)
    let header = #"{"alg":"ES256","kid":"\#(args[2])","typ":"JWT"}"#
    let payload = #"{"iss":"\#(args[3])","iat":\#(now),"exp":\#(now + lifetime),"aud":"appstoreconnect-v1"}"#
    let signingInput = base64URL(Data(header.utf8)) + "." + base64URL(Data(payload.utf8))
    let signature = try key.signature(for: Data(signingInput.utf8))
    print(signingInput + "." + base64URL(signature.rawRepresentation))
} catch {
    FileHandle.standardError.write(Data("asc-jwt: \(error.localizedDescription)\n".utf8))
    exit(70)
}
