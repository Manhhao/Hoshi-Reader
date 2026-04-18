//
//  EPUBGuideParser.swift
//  EPUBKit
//

import Foundation
import AEXML

protocol EPUBGuideParser {
    func parse(_ xmlElement: AEXMLElement?) -> EPUBGuide?
}

class EPUBGuideParserImplementation: EPUBGuideParser {
    func parse(_ xmlElement: AEXMLElement?) -> EPUBGuide? {
        guard let xmlElement, xmlElement.error == nil else {
            return nil
        }
        let references: [EPUBGuideReference] = xmlElement["reference"].all?
            .compactMap { element in
                guard
                    let type = element.attributes["type"],
                    let href = element.attributes["href"]
                else {
                    return nil
                }
                return EPUBGuideReference(
                    type: type,
                    href: href,
                    title: element.attributes["title"]
                )
            } ?? []
        guard !references.isEmpty else {
            return nil
        }
        return EPUBGuide(references: references)
    }
}
