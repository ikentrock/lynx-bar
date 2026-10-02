//
//  PeerCodeRequirement.swift
//  Shared
//

import CryptoKit
import Foundation
import Security

/// Builds code signing requirements that only match peers signed the
/// same way as the current process.
///
/// Lynx Bar is not built with an Apple Developer team, so the XPC
/// "same team" peer requirement can't be used. The app and its helper
/// require each other to be signed with the same certificate and to have
/// the expected signing identifier.
enum PeerCodeRequirement {
    /// How the current process is signed.
    enum Signer: Equatable, CustomStringConvertible {
        /// Signed with a certificate issued to an Apple Developer team.
        case team(String)
        /// Signed with a certificate that has no team, e.g. self-signed.
        /// The value is the lowercase hex SHA-1 of the leaf certificate.
        case certificate(sha1: String)

        var description: String {
            switch self {
            case .team(let team): "team \(team)"
            case .certificate(let sha1): "certificate \(sha1)"
            }
        }
    }

    /// Returns how the current process is signed, or `nil` if it is
    /// ad-hoc signed, unsigned, or its signature can't be read.
    static func currentSigner() -> Signer? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var cfInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard
            SecCodeCopySigningInformation(staticCode, flags, &cfInfo) == errSecSuccess,
            let info = cfInfo as? [String: Any]
        else {
            return nil
        }
        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .team(team)
        }
        guard
            let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else {
            return nil
        }
        let der = SecCertificateCopyData(leaf) as Data
        let sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined()
        return .certificate(sha1: sha1)
    }

    /// Returns a requirement matching a peer with the given signing
    /// identifier that is signed by `signer`, or `nil` if there is no
    /// signer or any component would make a malformed requirement.
    static func requirement(for signer: Signer?, peerIdentifier: String) -> String? {
        guard isValid(peerIdentifier, allowed: identifierCharacters) else {
            return nil
        }
        switch signer {
        case .team(let team):
            guard isValid(team, allowed: teamCharacters) else {
                return nil
            }
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(peerIdentifier)\""
        case .certificate(let sha1):
            guard sha1.count == 40, isValid(sha1, allowed: hexCharacters) else {
                return nil
            }
            return "certificate leaf = H\"\(sha1)\" and identifier \"\(peerIdentifier)\""
        case nil:
            return nil
        }
    }

    /// Returns a requirement matching a peer with the given signing
    /// identifier that is signed the same way as the current process.
    static func requirement(forPeerIdentifier identifier: String) -> String? {
        requirement(for: currentSigner(), peerIdentifier: identifier)
    }

    private static let identifierCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    private static let teamCharacters = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")

    private static func isValid(_ string: String, allowed: CharacterSet) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy(allowed.contains)
    }
}
