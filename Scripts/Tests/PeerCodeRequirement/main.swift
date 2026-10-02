//
//  main.swift
//  Tests
//

import Foundation

// MARK: Helper identity

expect(
    MenuBarItemServiceIdentity.serviceName(forHostIdentifier: "com.ikentrock.LynxBar")
        == "com.ikentrock.LynxBar.MenuBarItemService",
    "service name is the host identifier plus the suffix"
)
expect(
    MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: "com.ikentrock.LynxBar.MenuBarItemService")
        == "com.ikentrock.LynxBar",
    "host identifier strips the suffix"
)
expect(
    MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: "com.ikentrock.LynxBar") == nil,
    "an identifier without the suffix has no host"
)
expect(
    MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: ".MenuBarItemService") == nil,
    "the bare suffix has no host"
)

// MARK: Requirement strings

expect(
    PeerCodeRequirement.requirement(for: .team("ABCDE12345"), peerIdentifier: "com.example.App")
        == #"anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345" and identifier "com.example.App""#,
    "team signer requires same team and identifier"
)
expect(
    PeerCodeRequirement.requirement(
        for: .certificate(sha1: "e0ed98f7b2d56951b4e0a99082debaf25af66311"),
        peerIdentifier: "com.example.App"
    ) == #"certificate leaf = H"e0ed98f7b2d56951b4e0a99082debaf25af66311" and identifier "com.example.App""#,
    "certificate signer requires same leaf certificate and identifier"
)
expect(
    PeerCodeRequirement.requirement(for: nil, peerIdentifier: "com.example.App") == nil,
    "no signer means no requirement"
)
expect(
    PeerCodeRequirement.requirement(for: .team("ABCDE12345"), peerIdentifier: #"x" or anchor apple"#) == nil,
    "identifiers with quotes or spaces are rejected"
)
expect(
    PeerCodeRequirement.requirement(for: .team("ABCDE12345"), peerIdentifier: "") == nil,
    "an empty identifier is rejected"
)
expect(
    PeerCodeRequirement.requirement(for: .certificate(sha1: "not-hex"), peerIdentifier: "com.example.App") == nil,
    "a malformed certificate hash is rejected"
)
expect(
    PeerCodeRequirement.requirement(for: .team(#"AB"CD"#), peerIdentifier: "com.example.App") == nil,
    "a malformed team identifier is rejected"
)

// MARK: Current process signature

let signer = PeerCodeRequirement.currentSigner()
if let expectedSHA1 = ProcessInfo.processInfo.environment["EXPECT_CERT_SHA1"] {
    expect(
        signer == .certificate(sha1: expectedSHA1.lowercased()),
        "certificate-signed binary reports its leaf certificate (got \(String(describing: signer)))"
    )
} else {
    expect(signer == nil, "ad-hoc/linker-signed binary has no signer (got \(String(describing: signer)))")
}

finishTests("PeerCodeRequirement")
