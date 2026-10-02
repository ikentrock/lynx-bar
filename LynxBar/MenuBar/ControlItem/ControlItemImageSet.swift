//
//  ControlItemImageSet.swift
//  LynxBar
//

/// A named set of images that are used by control items.
///
/// An image set contains images for a control item in both the hidden and visible states.
struct ControlItemImageSet: Codable, Hashable, Identifiable {
    enum Name: String, Codable, Hashable {
        case arrow = "Arrow"
        case chevron = "Chevron"
        case door = "Door"
        case dot = "Dot"
        case ellipsis = "Ellipsis"
        case lynx = "Lynx"
        case sunglasses = "Sunglasses"
        case custom = "Custom"

        /// The name Ice stored for its "Ice Cube" set, replaced by ``lynx``.
        private static let legacyIceCube = "Ice Cube"

        init(from decoder: any Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            if rawValue == Self.legacyIceCube {
                self = .lynx
            } else if let name = Self(rawValue: rawValue) {
                self = name
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown image set name \(rawValue)"
                ))
            }
        }
    }

    let name: Name
    let hidden: ControlItemImage
    let visible: ControlItemImage

    var id: Int { hashValue }

    init(name: Name, hidden: ControlItemImage, visible: ControlItemImage) {
        self.name = name
        self.hidden = hidden
        self.visible = visible
    }

    init(name: Name, image: ControlItemImage) {
        self.init(name: name, hidden: image, visible: image)
    }

    private enum CodingKeys: String, CodingKey {
        case name, hidden, visible
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(Name.self, forKey: .name)
        if name == .lynx {
            // Stored "Ice Cube" sets point at deleted IceCube assets; always use
            // the current Lynx images.
            self = .lynx
            return
        }
        self.init(
            name: name,
            hidden: try container.decode(ControlItemImage.self, forKey: .hidden),
            visible: try container.decode(ControlItemImage.self, forKey: .visible)
        )
    }
}

extension ControlItemImageSet {
    /// The Lynx image set.
    static let lynx = ControlItemImageSet(
        name: .lynx,
        hidden: .catalog("LynxStroke"),
        visible: .catalog("LynxFill")
    )

    /// The default image set for the Lynx icon.
    static let defaultLynxIcon = lynx

    /// The image sets that the user can choose to display in the Lynx icon.
    static let userSelectableLynxIcons = [
        ControlItemImageSet(
            name: .arrow,
            hidden: .symbol("arrowshape.left.fill"),
            visible: .symbol("arrowshape.right.fill")
        ),
        ControlItemImageSet(
            name: .chevron,
            hidden: .symbol("chevron.left"),
            visible: .symbol("chevron.right")
        ),
        ControlItemImageSet(
            name: .door,
            hidden: .symbol("door.left.hand.closed"),
            visible: .symbol("door.left.hand.open")
        ),
        ControlItemImageSet(
            name: .dot,
            hidden: .catalog("DotFill"),
            visible: .catalog("DotStroke")
        ),
        ControlItemImageSet(
            name: .ellipsis,
            hidden: .catalog("EllipsisFill"),
            visible: .catalog("EllipsisStroke")
        ),
        lynx,
        ControlItemImageSet(
            name: .sunglasses,
            hidden: .symbol("sunglasses.fill"),
            visible: .symbol("sunglasses")
        ),
    ]
}
