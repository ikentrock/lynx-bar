//
//  Expect.swift
//  Tests
//

import Foundation

/// The number of failed expectations so far.
nonisolated(unsafe) var expectationFailures = 0

/// Records a failure if the condition is false.
func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if !condition() {
        expectationFailures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

/// Prints a summary and exits with a non-zero status if anything failed.
func finishTests(_ name: String) -> Never {
    if expectationFailures == 0 {
        print("PASS \(name)")
        exit(0)
    }
    print("\(expectationFailures) failure(s) in \(name)")
    exit(1)
}
