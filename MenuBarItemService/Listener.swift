//
//  Listener.swift
//  MenuBarItemService
//

import Foundation
import OSLog
import XPC

/// Accepts connections from the host app and answers its requests.
///
/// Every incoming connection must satisfy a code signing requirement that
/// only matches the host app, signed the same way as this service (see
/// ``PeerCodeRequirement``). If the service has no usable signature, or
/// its bundle identifier isn't a helper identifier, every connection is
/// refused.
enum Listener {
    /// The requirement that incoming peers must satisfy.
    private static let peerRequirement: String? = {
        guard
            let ownIdentifier = Bundle.main.bundleIdentifier,
            let host = MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: ownIdentifier)
        else {
            return nil
        }
        return PeerCodeRequirement.requirement(forPeerIdentifier: host)
    }()

    /// Handles a decoded request.
    private static func handle(_ request: MenuBarItemService.Request) -> MenuBarItemService.Response {
        switch request {
        case .start:
            Logger.default.debug("Listener received start request")
            return .start
        case .sourcePID(let window):
            return .sourcePID(SourcePIDCache.shared.pid(for: window))
        }
    }

    /// Handles an XPC event or message received on the given connection.
    private static func handle(event: xpc_object_t, on connection: xpc_connection_t) {
        guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
            Logger.default.notice("Listener connection event: \(MenuBarItemService.describe(event), privacy: .public)")
            return
        }
        guard let reply = xpc_dictionary_create_reply(event) else {
            return
        }
        do {
            let request = try MenuBarItemService.decode(MenuBarItemService.Request.self, from: event)
            try MenuBarItemService.encode(handle(request), into: reply)
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
        }
        xpc_connection_send_message(connection, reply)
    }

    /// Configures and resumes a new peer connection, or refuses it.
    private static func accept(_ connection: xpc_connection_t) {
        guard let peerRequirement else {
            Logger.default.error("Refusing connection: service is not signed with a certificate")
            xpc_connection_cancel(connection)
            return
        }
        guard xpc_connection_set_peer_code_signing_requirement(connection, peerRequirement) == 0 else {
            Logger.default.error("Refusing connection: invalid peer requirement \(peerRequirement, privacy: .public)")
            xpc_connection_cancel(connection)
            return
        }
        xpc_connection_set_event_handler(connection) { event in
            handle(event: event, on: connection)
        }
        xpc_connection_resume(connection)
    }

    /// Starts handling connections. Never returns.
    ///
    /// The service's `RunLoopType` is `NSRunLoop` (see its Info.plist), so
    /// the main run loop keeps running for ``SourcePIDCache``.
    static func run() -> Never {
        Logger.default.notice("Starting listener, peer requirement: \(peerRequirement ?? "none", privacy: .public)")
        xpc_main { connection in
            Listener.accept(connection)
        }
    }
}
