//
//  MenuBarItemService.swift
//  Shared
//

import Foundation
import XPC

/// Namespace for the `MenuBarItemService` XPC helper, which maps menu bar
/// item windows (owned by Control Center on macOS 26) to their source apps.
///
/// The service name is derived from the app's bundle identifier; see
/// ``MenuBarItemServiceIdentity``.
enum MenuBarItemService { }

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}

// MARK: - Message Coding

extension MenuBarItemService {
    /// An error that occurs when a message can't be encoded or decoded.
    struct MessageError: Error, CustomStringConvertible {
        let description: String
    }

    /// The dictionary key for a message's JSON payload.
    private static let payloadKey = "payload"

    /// Encodes a value as JSON into the given XPC dictionary.
    static func encode<T: Encodable>(_ value: T, into dictionary: xpc_object_t) throws {
        let data = try JSONEncoder().encode(value)
        data.withUnsafeBytes { buffer in
            xpc_dictionary_set_data(dictionary, payloadKey, buffer.baseAddress, buffer.count)
        }
    }

    /// Decodes a JSON value from the given XPC dictionary.
    static func decode<T: Decodable>(_ type: T.Type, from dictionary: xpc_object_t) throws -> T {
        var length = 0
        guard let bytes = xpc_dictionary_get_data(dictionary, payloadKey, &length) else {
            throw MessageError(description: "Message has no payload")
        }
        return try JSONDecoder().decode(type, from: Data(bytes: bytes, count: length))
    }

    /// Returns a readable description of an XPC object, e.g. an error.
    static func describe(_ object: xpc_object_t) -> String {
        if
            xpc_get_type(object) == XPC_TYPE_ERROR,
            let cString = xpc_dictionary_get_string(object, XPC_ERROR_KEY_DESCRIPTION)
        {
            return String(cString: cString)
        }
        return String(describing: object)
    }
}
