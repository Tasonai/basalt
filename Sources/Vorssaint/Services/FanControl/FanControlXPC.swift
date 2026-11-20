// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security
import CryptoKit

enum FanControlIdentifiers {
    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.tasonai.basalt.dev"
    #else
    static let appBundleID = "com.tasonai.basalt"
    #endif

    static let helperID = "\(appBundleID).fan-control"
    static let plistName = "\(helperID).plist"

    static var appCodeRequirement: String {
        codeRequirement(for: appBundleID)
    }

    static var helperCodeRequirement: String {
        codeRequirement(for: helperID)
    }

    private static func codeRequirement(for identifier: String) -> String {
        #if !(VORSSAINT_DEVELOPMENT || VORSSAINT_SELF_SIGNED)
        if let team = currentTeamIdentifier(), !team.isEmpty {
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(identifier)\""
        }
        #endif
        guard let hash = currentLeafCertificateSHA1() else {
            return "identifier \"\(identifier)\" and certificate leaf = H\"0000000000000000000000000000000000000000\""
        }
        return "identifier \"\(identifier)\" and certificate leaf = H\"\(hash)\""
    }

    private static func currentSigningInfo() -> [String: Any]? {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess,
              let selfCode = dynamicCode else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let staticSelfCode = staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticSelfCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return nil
        }
        return info
    }

    private static func currentTeamIdentifier() -> String? {
        guard let info = currentSigningInfo(),
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else {
            return nil
        }
        return team
    }

    private static func currentLeafCertificateSHA1() -> String? {
        guard let info = currentSigningInfo(),
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else {
            return nil
        }

        let data = SecCertificateCopyData(leaf) as Data
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@objc protocol FanControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func startMaximumCooling(withReply reply: @escaping (Data) -> Void)
    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreAutomatic(withReply reply: @escaping (Data) -> Void)
}

enum FanControlIPC {
    static func encode(_ response: FanControlResponse) -> Data {
        // Every value in this closed response model is JSON encodable. Keeping
        // one deterministic fallback avoids ever violating the XPC reply shape.
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"fans":[],"isCooling":false},"error":"controlFailed"}"#.utf8)
    }

    static func decode(_ data: Data) -> FanControlResponse? {
        try? JSONDecoder().decode(FanControlResponse.self, from: data)
    }

    static func encode(_ configuration: FanControlConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration)
    }

    static func decodeConfiguration(_ data: Data) -> FanControlConfiguration? {
        guard let configuration = try? JSONDecoder().decode(FanControlConfiguration.self,
                                                              from: data),
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}
