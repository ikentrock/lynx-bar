//
//  main.swift
//  Tests
//

import CoreGraphics
import Foundation

func item(_ id: String?, _ x: CGFloat, own: Bool = false) -> HostedItem {
    HostedItem(bundleIdentifier: id, frame: CGRect(x: x, y: 0, width: 30, height: 30), isOwn: own)
}

// Entries

let items = [
    item("com.example.stats", 400), item("com.example.chat", 100), item("com.example.stats", 200),
    item("com.example.visible", 600), item(nil, 50), item("com.ikentrock.LynxBar", 300, own: true),
    item("com.example.stats", 350),
]
let entries = HostedShelfLayout.entries(
    items: items,
    apps: ["com.example.chat", "com.example.stats", "com.ikentrock.LynxBar"]
)
expect(
    entries.map(\.bundleIdentifier) == [
        "com.example.chat", "com.example.stats", "com.example.stats", "com.example.stats",
    ],
    "entries are the section's icons, left to right, without our own or unknown ones"
)
expect(entries.map(\.index) == [0, 0, 1, 2], "an app's icons are numbered left to right")
expect(entries.map(\.frame.minX) == [100, 200, 350, 400], "entries keep their frames")
expect(HostedShelfLayout.entries(items: items, apps: []).isEmpty, "no apps, no entries")

// Position

let icons: [(bundleIdentifier: String?, frame: CGRect)] = items.map { ($0.bundleIdentifier, $0.frame) }
expect(
    HostedShelfLayout.position(ofIndex: 1, bundleIdentifier: "com.example.stats", in: icons) == 6,
    "the second stats icon from the left is the one at x 350"
)
expect(
    HostedShelfLayout.position(ofIndex: 0, bundleIdentifier: "com.example.stats", in: icons) == 2,
    "the first stats icon is the one at x 200"
)
expect(
    HostedShelfLayout.position(ofIndex: 3, bundleIdentifier: "com.example.stats", in: icons) == nil,
    "an index past the app's icons finds nothing"
)
expect(
    HostedShelfLayout.position(ofIndex: 0, bundleIdentifier: "com.example.gone", in: icons) == nil,
    "an app without icons finds nothing"
)

// Settling

let expected: Set = ["a", "b", "c"]
expect(
    HostedShelfLayout.isSettled(
        present: ["a", "b", "c", "x"], previous: nil, expected: expected,
        elapsed: .zero, minimumWait: .milliseconds(300)
    ),
    "settled once every expected app is drawn"
)
expect(
    !HostedShelfLayout.isSettled(
        present: ["a", "b"], previous: ["a", "b"], expected: expected,
        elapsed: .milliseconds(100), minimumWait: .milliseconds(300)
    ),
    "a stable partial bar isn't settled before the minimum wait"
)
expect(
    HostedShelfLayout.isSettled(
        present: ["a", "b"], previous: ["a", "b"], expected: expected,
        elapsed: .milliseconds(300), minimumWait: .milliseconds(300)
    ),
    "a stable partial bar is settled after the minimum wait: some apps own no icon"
)
expect(
    !HostedShelfLayout.isSettled(
        present: ["a", "b"], previous: ["a"], expected: expected,
        elapsed: .seconds(1), minimumWait: .milliseconds(300)
    ),
    "a bar that is still changing isn't settled"
)
expect(
    !HostedShelfLayout.isSettled(
        present: [], previous: [], expected: expected,
        elapsed: .seconds(1), minimumWait: .milliseconds(300)
    ),
    "an empty bar isn't settled"
)

// Pixel rectangles

let window = CGRect(x: 0, y: 0, width: 1512, height: 33)
expect(
    HostedShelfLayout.pixelRect(
        of: CGRect(x: 100, y: 0, width: 30, height: 33),
        windowBounds: window, scale: 2, imageSize: CGSize(width: 3024, height: 66)
    ) == CGRect(x: 200, y: 0, width: 60, height: 66),
    "frames are scaled to the image's pixels on a Retina display"
)
expect(
    HostedShelfLayout.pixelRect(
        of: CGRect(x: 1500, y: 0, width: 30, height: 33),
        windowBounds: window, scale: 1, imageSize: CGSize(width: 1512, height: 33)
    ) == CGRect(x: 1500, y: 0, width: 12, height: 33),
    "frames are clipped to the image"
)
expect(
    HostedShelfLayout.pixelRect(
        of: CGRect(x: 2000, y: 0, width: 30, height: 33),
        windowBounds: window, scale: 1, imageSize: CGSize(width: 1512, height: 33)
    ) == nil,
    "a frame outside the image has no pixels"
)

// Changed pixels

let still = Data([10, 10, 10, 255, 20, 20, 20, 255, 30, 30, 30, 255, 40, 40, 40, 255])
var oneChanged = still
oneChanged[4] = 200
var slightlyChanged = still
slightlyChanged[0] = 14
expect(
    HostedShelfLayout.changedFraction(still, still, bytesPerPixel: 4, tolerance: 8) == 0,
    "identical images have no changed pixels"
)
expect(
    HostedShelfLayout.changedFraction(still, oneChanged, bytesPerPixel: 4, tolerance: 8) == 0.25,
    "one changed pixel of four is a quarter"
)
expect(
    HostedShelfLayout.changedFraction(still, slightlyChanged, bytesPerPixel: 4, tolerance: 8) == 0,
    "differences within the tolerance don't count"
)
expect(
    HostedShelfLayout.changedFraction(still, still.prefix(8), bytesPerPixel: 4, tolerance: 8) == 1,
    "images of different sizes differ entirely"
)

finishTests("HostedShelfLayout")
