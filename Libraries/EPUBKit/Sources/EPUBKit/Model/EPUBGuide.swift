//
//  EPUBGuide.swift
//  EPUBKit
//

import Foundation

public struct EPUBGuide {
    public var references: [EPUBGuideReference]
}

public struct EPUBGuideReference {
    public var type: String
    public var href: String
    public var title: String?
}
