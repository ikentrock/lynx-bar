//
//  HostedShelfLayout.swift
//  LynxBar
//

import CoreGraphics
import Foundation

/// One icon shown in the Lynx Shelf on macOS 27.
///
/// An app can own several icons, so an icon is named by its app and its
/// place among that app's icons, left to right. That place is how the icon
/// is found again in the bar to press it.
struct HostedShelfEntry: Hashable {
    let bundleIdentifier: String
    let index: Int
    let frame: CGRect

    /// What names the icon in every agent window: its app and index. Its
    /// frame can differ between windows.
    struct Key: Hashable {
        let bundleIdentifier: String
        let index: Int
    }

    var key: Key { Key(bundleIdentifier: bundleIdentifier, index: index) }
}

/// Pure logic of the Lynx Shelf on macOS 27, so it can be tested without
/// the menu bar.
enum HostedShelfLayout {
    /// The shelf entries for the icons of `apps` in `items`, left to right.
    /// Our own icons and icons without an app are left out.
    static func entries(items: [HostedItem], apps: Set<String>) -> [HostedShelfEntry] {
        var counts = [String: Int]()
        return items
            .filter { !$0.isOwn }
            .sorted { $0.frame.minX < $1.frame.minX }
            .compactMap { item in
                guard let id = item.bundleIdentifier, apps.contains(id) else {
                    return nil
                }
                let index = counts[id, default: 0]
                counts[id] = index + 1
                return HostedShelfEntry(bundleIdentifier: id, index: index, frame: item.frame)
            }
    }

    /// The position in `frames` of the `index`th icon of an app, left to
    /// right, given each icon's app and frame, or `nil` if it has fewer.
    static func position(
        ofIndex index: Int,
        bundleIdentifier: String,
        in icons: [(bundleIdentifier: String?, frame: CGRect)]
    ) -> Int? {
        let matching = icons.indices
            .filter { icons[$0].bundleIdentifier == bundleIdentifier }
            .sorted { icons[$0].frame.minX < icons[$1].frame.minX }
        return matching.indices.contains(index) ? matching[index] : nil
    }

    /// Whether the bar has settled after lifting the allowlist for
    /// `expected`: every expected app is drawn, or the drawn ones stopped
    /// changing after `minimumWait`. Some running apps own no icon, so
    /// waiting for all of them could only end at the timeout.
    static func isSettled(
        present: Set<String>,
        previous: Set<String>?,
        expected: Set<String>,
        elapsed: Duration,
        minimumWait: Duration
    ) -> Bool {
        if expected.isSubset(of: present) {
            return true
        }
        return elapsed >= minimumWait && !present.isEmpty && present == previous
    }

    /// The fraction of pixels that differ between two images of the same
    /// size, `bytesPerPixel` bytes each: a pixel differs if any of its bytes
    /// differs by more than `tolerance`. Images of different sizes differ
    /// entirely.
    static func changedFraction(_ old: Data, _ new: Data, bytesPerPixel: Int, tolerance: UInt8) -> Double {
        guard old.count == new.count, bytesPerPixel > 0, old.count >= bytesPerPixel else {
            return 1
        }
        let pixelCount = old.count / bytesPerPixel
        var changed = 0
        old.withUnsafeBytes { oldBytes in
            new.withUnsafeBytes { newBytes in
                for pixel in 0..<pixelCount {
                    let start = pixel * bytesPerPixel
                    for byte in start..<(start + bytesPerPixel) {
                        let difference = abs(Int(oldBytes[byte]) - Int(newBytes[byte]))
                        if difference > Int(tolerance) {
                            changed += 1
                            break
                        }
                    }
                }
            }
        }
        return Double(changed) / Double(pixelCount)
    }

    /// The pixel rectangle of `frame` in an image of a window at
    /// `windowBounds`, `scale` pixels per point, or `nil` if it falls
    /// outside the image.
    static func pixelRect(
        of frame: CGRect,
        windowBounds: CGRect,
        scale: CGFloat,
        imageSize: CGSize
    ) -> CGRect? {
        let rect = CGRect(
            x: (frame.minX - windowBounds.minX) * scale,
            y: (frame.minY - windowBounds.minY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
        .integral
        .intersection(CGRect(origin: .zero, size: imageSize))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else {
            return nil
        }
        return rect
    }
}
