//
//  MenuBarItemServiceConnection.swift
//  LynxBar
//

import Foundation
import OSLog
import XPC

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's logger.
        private let logger: Logger

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let logger = Logger(category: "MenuBarItemService.Connection")
            self.session = Session(queue: queue, logger: logger)
            self.logger = logger
        }

        /// Starts the connection.
        ///
        /// - Returns: `nil` if the service answered, otherwise a description
        ///   of why it couldn't be reached.
        func start() async -> String? {
            logger.debug("Starting MenuBarItemService connection")
            do {
                let response = try session.send(request: .start)
                guard case .start = response else {
                    return "Start request returned invalid response \(response)"
                }
                return nil
            } catch {
                let reason = String(describing: error)
                logger.error("MenuBarItemService start failed: \(reason, privacy: .public)")
                return reason
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            do {
                let response = try session.send(request: .sourcePID(window))
                guard case .sourcePID(let pid) = response else {
                    logger.error("Source PID request returned invalid response \(String(describing: response))")
                    return nil
                }
                return pid
            } catch {
                // Debug level: when the helper is refused, this fails for every
                // window on every refresh. `start()` already logged the reason.
                logger.debug("Source PID request failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }
}

// MARK: - MenuBarItemService.ConnectionError

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// An error that prevents a request from reaching the service.
    enum ConnectionError: Error, CustomStringConvertible {
        /// The app has no certificate signature, so it can't require one from the service.
        case unsigned
        /// The generated peer requirement was rejected by XPC.
        case invalidRequirement(String)
        /// XPC returned an error, e.g. "Peer Forbidden".
        case xpc(String)

        var description: String {
            switch self {
            case .unsigned:
                "Lynx Bar is not signed with a certificate, so it won't connect to its helper"
            case .invalidRequirement(let requirement):
                "Invalid peer requirement: \(requirement)"
            case .xpc(let description):
                "XPC error: \(description)"
            }
        }
    }
}

// MARK: - MenuBarItemService.Session

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A wrapper around an XPC connection to the service.
    private final class Session: Sendable {
        /// A session's underlying storage. Only accessed under ``storage``'s lock.
        private final class Storage: @unchecked Sendable {
            private let serviceName = MenuBarItemServiceIdentity.serviceName(
                forHostIdentifier: Bundle.main.bundleIdentifier ?? ""
            )
            private let peerRequirement: String?
            private var connection: xpc_connection_t?
            private let queue: DispatchQueue
            private let logger: Logger

            init(queue: DispatchQueue, logger: Logger) {
                self.queue = queue
                self.logger = logger
                self.peerRequirement = PeerCodeRequirement.requirement(forPeerIdentifier: serviceName)
            }

            private func getOrCreateConnection() throws -> xpc_connection_t {
                if let connection {
                    return connection
                }
                guard let peerRequirement else {
                    throw ConnectionError.unsigned
                }
                let connection = xpc_connection_create(serviceName, queue)
                guard xpc_connection_set_peer_code_signing_requirement(connection, peerRequirement) == 0 else {
                    xpc_connection_cancel(connection)
                    throw ConnectionError.invalidRequirement(peerRequirement)
                }
                let logger = logger
                xpc_connection_set_event_handler(connection) { event in
                    if xpc_get_type(event) == XPC_TYPE_ERROR {
                        logger.warning("Connection event: \(MenuBarItemService.describe(event), privacy: .public)")
                    }
                }
                xpc_connection_resume(connection)
                logger.info("Connecting to \(self.serviceName, privacy: .public) requiring \(peerRequirement, privacy: .public)")
                self.connection = connection
                return connection
            }

            func cancel(reason: String) {
                guard let connection = connection.take() else {
                    return
                }
                logger.debug("Cancelling connection: \(reason)")
                xpc_connection_cancel(connection)
            }

            func send(request: Request) throws -> Response {
                let connection = try getOrCreateConnection()
                let message = xpc_dictionary_create_empty()
                try MenuBarItemService.encode(request, into: message)
                let reply = xpc_connection_send_message_with_reply_sync(connection, message)
                if xpc_get_type(reply) == XPC_TYPE_ERROR {
                    // An interrupted connection reconnects on the next message;
                    // any other error invalidates it, so start over next time.
                    if reply !== XPC_ERROR_CONNECTION_INTERRUPTED {
                        cancel(reason: "Received error \(MenuBarItemService.describe(reply))")
                    }
                    throw ConnectionError.xpc(MenuBarItemService.describe(reply))
                }
                return try MenuBarItemService.decode(Response.self, from: reply)
            }
        }

        /// Protected storage for the underlying XPC connection.
        private let storage: OSAllocatedUnfairLock<Storage>

        /// Creates a new session.
        init(queue: DispatchQueue, logger: Logger) {
            self.storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue, logger: logger))
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        /// Sends the given request to the service and returns the response.
        func send(request: Request) throws -> Response {
            try storage.withLock { try $0.send(request: request) }
        }
    }
}
