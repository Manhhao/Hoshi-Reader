//
//  TtuConverter.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation
import ZIPFoundation
import AEXML

struct TtuConverter {
    private struct StaticData: Codable {
        let title: String
        let styleSheet: String
        let elementHtml: String
        let sections: [Section]
    }
    
    private struct Section: Codable {
        let reference: String
        let charactersWeight: Int
        let label: String?
        let startCharacter: Int?
        var characters: Int?
        let parentChapter: String?
    }
    
    private struct XHTMLFile {
        let fileName: String
        let label: String?
        let html: String
    }
    
    static func convertFromTtu(bookData: URL, to directory: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        
        try FileManager.default.unzipItem(at: bookData, to: temp)
        
        let staticData = try JSONDecoder().decode(StaticData.self, from: Data(contentsOf: temp.appendingPathComponent("staticdata.json")))
        let folderName = BookStorage.sanitizeFileName(staticData.title)
        let destinationFolder = directory.appendingPathComponent(folderName)
        if FileManager.default.fileExists(atPath: destinationFolder.path(percentEncoded: false)) {
            return destinationFolder
        }
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        
        let epubURL = destinationFolder
            .appendingPathComponent(folderName)
            .appendingPathExtension("epub")
        let archive = try Archive(
            url: epubURL,
            accessMode: .create,
            pathEncoding: .utf8
        )
        
        // mimetype
        let mimetype = "application/epub+zip"
        try archive.addEntry(with: "mimetype", contents: mimetype, compressionMethod: .none)
        
        // stylesheet.css
        try archive.addEntry(with: "item/stylesheet.css", contents: staticData.styleSheet, compressionMethod: .deflate)
        
        // META-INF/container.xml
        let container =
        """
        <?xml version="1.0"?>
        <container
         version="1.0"
         xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
        >
        <rootfiles>
        <rootfile
         full-path="item/standard.opf"
         media-type="application/oebps-package+xml"
        />
        </rootfiles>
        </container>
        """
        try archive.addEntry(with: "META-INF/container.xml", contents: container, compressionMethod: .deflate)
        
        // images
        let blobs = temp.appendingPathComponent("blobs")
        var imagePaths: [String] = []
        let imageFiles = try collectImageFiles(from: blobs)
        for imageFile in imageFiles {
            let relativePath = imageFile.standardizedFileURL.pathComponents
                .dropFirst(blobs.standardizedFileURL.pathComponents.count)
                .joined(separator: "/")
            imagePaths.append(relativePath)
            try archive.addEntry(with: "item/\(relativePath)", fileURL: imageFile, compressionMethod: .deflate)
        }
        
        // cover
        let cover = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix("cover.") })
        if let cover {
            try FileManager.default.moveItem(at: cover, to: destinationFolder.appendingPathComponent(cover.lastPathComponent))
        }
        
        // xhtml/*.xhtml
        let xhtmlFiles = splitElementHTML(html: normalizeTagsToXHTML(normalizeImages(staticData.elementHtml)), sections: staticData.sections)
        for file in xhtmlFiles {
            let formatted = generateXHTML(file, title: escapeXML(staticData.title))
            try archive.addEntry(with: "item/xhtml/\(file.fileName)", contents: formatted, compressionMethod: .deflate)
        }
        
        // item/navigation-documents.xhtml
        let navigationDocuments = generateNavigationDocuments(xhtmlFiles: xhtmlFiles)
        try archive.addEntry(with: "item/navigation-documents.xhtml", contents: navigationDocuments, compressionMethod: .deflate)
        
        // item/standard.opf
        let standard = generateOPF(imagePaths: imagePaths, xhtmlFiles: xhtmlFiles, title: escapeXML(staticData.title))
        try archive.addEntry(with: "item/standard.opf", contents: standard, compressionMethod: .deflate)
        
        // store source
        // try FileManager.default.copyItem(at: bookData, to: destinationFolder.appendingPathComponent(bookData.lastPathComponent))
        
        // process converted book
        let document = try BookStorage.loadEpub(epubURL)
        let coverPath = cover.map { "Books/\(folderName)/\($0.lastPathComponent)" }
        let metadata = BookMetadata(
            title: staticData.title,
            epub: epubURL.lastPathComponent,
            cover: coverPath,
            folder: folderName,
            lastAccess: Date()
        )
        let bookInfo = BookProcessor.process(document: document)
        try BookStorage.save(metadata, inside: destinationFolder, as: FileNames.metadata)
        try BookStorage.save(bookInfo, inside: destinationFolder, as: FileNames.bookinfo)
        return destinationFolder
    }
    
    static func convertToTtu(bookFolder: URL, to directory: URL) throws -> URL? {
        guard let metadata = BookStorage.loadMetadata(root: bookFolder),
              let bookInfo = BookStorage.loadBookInfo(root: bookFolder),
              let epub = metadata.epub else {
            return nil
        }
        
        let epubURL = bookFolder.appendingPathComponent(epub)
        let document = try BookStorage.loadEpub(epubURL)
        let fileName = "bookdata_1_6_\(bookInfo.characterCount)_\(Int(Date.now.timeIntervalSince1970 * 1000))_\(Int(metadata.lastAccess.timeIntervalSince1970 * 1000)).zip"
        
        var elementParts: [String] = []
        var sections: [Section] = []
        var currentParent: String?
        for item in document.spine.items {
            guard let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            
            let chapterInfo = bookInfo.chapterInfo[manifestItem.path]
            let characters = chapterInfo?.chapterCount ?? 0
            let ttuNoText = characters == 0 ? " ttu-no-text" : ""
            
            let xhtmlURL = document.contentDirectory.appendingPathComponent(manifestItem.path)
            let content = try String(contentsOf: xhtmlURL, encoding: .utf8)
            let htmlClass = String(content.firstMatch(of: /<html\b[^>]*\bclass="([^"]*)"/)?.1 ?? "")
            let bodyClass = String(content.firstMatch(of: /<body\b[^>]*\bclass="([^"]*)"/)?.1 ?? "")
            let bodyHtml = String(content.firstMatch(of: /<body\b[^>]*>([\s\S]*)<\/body>/)?.1 ?? "")
            let htmlClasses = Self.classList("ttu-book-html-wrapper", htmlClass, ttuNoText)
            let bodyClasses = Self.classList("ttu-book-body-wrapper", bodyClass, ttuNoText)
            let ttuBodyHtml = Self.normalizeTagsToHTML(Self.rewriteImages(bodyHtml, path: manifestItem.path))
            elementParts.append("<div id=\"ttu-\(item.idref)\"><div class=\"\(htmlClasses)\"><div class=\"\(bodyClasses)\">\(ttuBodyHtml)</div></div></div>")
            
            let reference = "ttu-\(item.idref)"
            let startCharacter = chapterInfo?.currentTotal ?? 0
            
            let label = Self.tocLabel(for: manifestItem.path, in: document.tableOfContents)
            if let label {
                currentParent = reference
                sections.append(Section(
                    reference: reference,
                    charactersWeight: max(characters, 1),
                    label: label,
                    startCharacter: startCharacter,
                    characters: 0,
                    parentChapter: nil
                ))
            } else if let currentParent {
                sections.append(Section(
                    reference: reference,
                    charactersWeight: max(characters, 1),
                    label: nil,
                    startCharacter: nil,
                    characters: nil,
                    parentChapter: currentParent
                ))
            } else {
                currentParent = reference
                sections.append(Section(
                    reference: reference,
                    charactersWeight: max(characters, 1),
                    label: "Preface",
                    startCharacter: startCharacter,
                    characters: 0,
                    parentChapter: nil
                ))
            }
        }
        
        for i in 0..<sections.count where sections[i].label != nil {
            let nextLabeledSection = sections[(i+1)...].first(where: { $0.label != nil })
            let nextStart = nextLabeledSection?.startCharacter ?? bookInfo.characterCount
            sections[i].characters = nextStart - sections[i].startCharacter!
        }
        
        let stylesheet = try Self.cssFiles(document: document)
            .map { path in
                let url = document.contentDirectory.appendingPathComponent(path)
                return try String(contentsOf: url, encoding: .utf8)
            }
            .joined()
        
        let bookDataURL = directory.appendingPathComponent(fileName)
        let archive = try Archive(
            url: bookDataURL,
            accessMode: .create,
            pathEncoding: .utf8
        )
        
        let elementHtml = elementParts.joined()
        let staticData = StaticData(title: metadata.title, styleSheet: stylesheet, elementHtml: elementHtml, sections: sections)
        let jsonData = try JSONEncoder().encode(staticData)
        try archive.addEntry(with: "staticdata.json", contents: String(data: jsonData, encoding: .utf8)!, compressionMethod: .deflate)
        
        let images = document.manifest.items.values.filter { $0.mediaType == .gif || $0.mediaType == .jpeg || $0.mediaType == .png || $0.mediaType == .svg }
        for image in images {
            let imageURL = document.contentDirectory.appendingPathComponent(image.path)
            guard FileManager.default.fileExists(atPath: imageURL.path(percentEncoded: false)) else { continue }
            try archive.addEntry(with: "blobs/\(image.path)", fileURL: imageURL, compressionMethod: .none)
        }
        
        if let coverURL = metadata.coverURL {
            try archive.addEntry(with: "cover.\(coverURL.pathExtension)", fileURL: coverURL, compressionMethod: .none)
        }
        
        return bookDataURL
    }
    
    private static func normalizeTagsToXHTML(_ html: String) -> String {
        html
            .replacing("<br>", with: "<br/>")
            .replacing(/(<img [^>]+)>/) { "\($0.1)/>" }
    }
    
    private static func normalizeTagsToHTML(_ html: String) -> String {
        html
            .replacing(/<br\s*\/>/, with: "<br>")
            .replacing(/<img\b([^>]*)\/>/) { "<img\($0.1)>" }
    }
    
    private static func normalizeImages(_ html: String) -> String {
        html
            .replacing(/data:image\/[^;"]+;ttu:([^;"]+);base64,[^"]*/) { "../\(String($0.1))" }
            .replacing(/ttu:([^"']+)/) { "../\(String($0.1))" }
    }
    
    private static func collectImageFiles(from blobs: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: blobs.path(percentEncoded: false)) else {
            return []
        }
        
        let imageFiles = FileManager.default.enumerator(
            at: blobs,
            includingPropertiesForKeys: [.isRegularFileKey]
        )!
        
        var files: [URL] = []
        for case let fileURL as URL in imageFiles {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "gif" || ext == "svg" {
                files.append(fileURL)
            }
        }
        
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    private static func splitElementHTML(html: String, sections: [Section]) -> [XHTMLFile] {
        let split = sections.compactMap { section -> (Section, String.Index)? in
            guard let range = html.range(of: "<div id=\"\(section.reference)\"") else {
                return nil
            }
            return (section, range.lowerBound)
        }.sorted { $0.1 < $1.1 }
        
        return split.enumerated().map { index, item in
            let end = index + 1 < split.count ? split[index + 1].1 : html.endIndex
            return XHTMLFile(
                fileName: "\(item.0.reference.dropFirst(4)).xhtml",
                label: item.0.label,
                html: String(html[item.1..<end]))
        }
    }
    
    private static func generateXHTML(_ xhtml: XHTMLFile, title: String) -> String {
        var content = String(xhtml.html
            .dropFirst("<div id=\"ttu-\(xhtml.fileName.dropLast(6))\">".count)
            .dropLast(18))
        let htmlClass = (content.firstMatch(of: /ttu-book-html-wrapper\s*([^"]*)"/)?.1 ?? "")
            .replacing("ttu-no-text", with: "").trimmingCharacters(in: .whitespaces)
        let bodyClass = (content.firstMatch(of: /ttu-book-body-wrapper\s*([^"]*)"/)?.1 ?? "")
            .replacing("ttu-no-text", with: "").trimmingCharacters(in: .whitespaces)
        content = content
            .replacing(/<div class="ttu-book-html-wrapper[^"]*">/, with: "")
            .replacing(/<div class="ttu-book-body-wrapper[^"]*">/, with: "")
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html
         xmlns="http://www.w3.org/1999/xhtml"
         xmlns:epub="http://www.idpf.org/2007/ops"
         xml:lang="ja"
         class="\(htmlClass)"
        >
        <head>
        <meta charset="UTF-8"/>
        <title>\(title)</title>
        <link rel="stylesheet" type="text/css" href="../stylesheet.css"/>
        </head>
        <body class="\(bodyClass)">
        \(content)
        </body>
        </html>
        """
    }
    
    private static func generateNavigationDocuments(xhtmlFiles: [XHTMLFile]) -> String {
        let navItems = xhtmlFiles.filter { $0.label != nil }.map {
            "<li><a href=\"xhtml/\($0.fileName)\">\(escapeXML($0.label!))</a></li>"
        }.joined(separator: "\n")
        let tocItem = xhtmlFiles.first { $0.fileName.contains("toc") }.map {
            "<li><a epub:type=\"toc\" href=\"xhtml/\($0.fileName)\">\(escapeXML($0.label ?? "toc"))</a></li>"
        } ?? ""
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html
         xmlns="http://www.w3.org/1999/xhtml"
         xmlns:epub="http://www.idpf.org/2007/ops"
         xml:lang="ja"
        >
        <head>
        <meta charset="UTF-8"/>
        <title>Navigation</title>
        </head>
        <body>
        <nav epub:type="toc" id="toc">
        <h1>Navigation</h1>
        <ol>
        \(navItems)
        </ol>
        </nav>
        
        <nav epub:type="landmarks" id="guide">
        <h1>Guide</h1>
        <ol>
        \(tocItem)
        </ol>
        </nav>
        
        </body>
        </html>
        """
    }
    
    private static func imageMediaType(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": "image/png"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        default: "image/jpeg"
        }
    }
    
    private static func generateOPF(imagePaths: [String], xhtmlFiles: [XHTMLFile], title: String) -> String {
        let imageManifest = imagePaths.map { path in
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let isCover = name == "cover"
            let properties = isCover ? " properties=\"cover-image\"" : ""
            return "<item media-type=\"\(imageMediaType(path))\" id=\"\(isCover ? "cover" : "i-\(name)")\" href=\"\(path)\"\(properties)/>"
        }.joined(separator: "\n")
        
        let xhtmlManifest = xhtmlFiles.sorted { $0.fileName < $1.fileName }.map {
            let properties = $0.html.contains("<svg") ? " properties=\"svg\"" : ""
            return "<item media-type=\"application/xhtml+xml\" id=\"\($0.fileName.dropLast(6))\" href=\"xhtml/\($0.fileName)\"\(properties)/>"
        }.joined(separator: "\n")
        
        let spineProgression = xhtmlFiles.map {
            "<itemref linear=\"yes\" idref=\"\($0.fileName.dropLast(6))\"/>"
        }.joined(separator: "\n")
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package
         xmlns="http://www.idpf.org/2007/opf"
         version="3.0"
         xml:lang="ja"
         unique-identifier="book-uuid"
        >
        
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        
        <!-- 作品名 -->
        <dc:title id="title">\(title)</dc:title>
        
        <!-- 言語 -->
        <dc:language>ja</dc:language>
        
        <!-- ファイルid -->
        <dc:identifier id="book-uuid">\(UUID().uuidString)</dc:identifier>
        
        </metadata>
        
        <manifest>
        
        <!-- navigation -->
        <item media-type="application/xhtml+xml" id="nav" href="navigation-documents.xhtml" properties="nav"/>
        
        <!-- style -->
        <item media-type="text/css" id="stylesheet" href="stylesheet.css"/>
        
        <!-- image -->
        \(imageManifest)
        
        <!-- xhtml -->
        \(xhtmlManifest)
        
        </manifest>
        
        <spine page-progression-direction="rtl">
        
        \(spineProgression)
        
        </spine>
        
        </package>
        """
    }
    
    private static func tocLabel(for path: String, in toc: EPUBTableOfContents) -> String? {
        if let item = toc.item?.components(separatedBy: "#").first {
            if item == path || item.hasSuffix(path) || path.hasSuffix(item) {
                return toc.label
            }
        }
        for child in toc.subTable ?? [] {
            if let label = tocLabel(for: path, in: child) {
                return label
            }
        }
        return nil
    }
    
    private static func rewriteImages(_ html: String, path: String) -> String {
        let rewrite: (String) -> String = { src in
            let base = URL(fileURLWithPath: path).deletingLastPathComponent()
            let imagePath = URL(fileURLWithPath: src, relativeTo: base)
                .standardized
                .relativePath
            return "data:image/gif;ttu:\(imagePath);base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=="
        }
        
        return html
            .replacing(/(<img\b[^>]*\bsrc=")([^"]+)(")/) { match in
                "\(match.1)\(rewrite(String(match.2)))\(match.3)"
            }
            .replacing(/(<image\b[^>]*\sxlink:href=")([^"]+)(")/) { match in
                "\(match.1)\(rewrite(String(match.2)))\(match.3)"
            }
            .replacing(/(<image\b[^>]*\shref=")([^"]+)(")/) { match in
                "\(match.1)\(rewrite(String(match.2)))\(match.3)"
            }
    }
    
    private static func cssFiles(document: EPUBDocument) throws -> [String] {
        let containerURL = document.directory
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        let container = try AEXMLDocument(xml: Data(contentsOf: containerURL))
        guard let opfPath = container.root["rootfiles"]["rootfile"].attributes["full-path"] else {
            return []
        }
        
        let opfURL = document.directory.appendingPathComponent(opfPath)
        let opf = try AEXMLDocument(xml: Data(contentsOf: opfURL))
        return opf.root["manifest"]["item"].all?
            .compactMap { item in
                guard item.attributes["media-type"] == "text/css" else {
                    return nil
                }
                return item.attributes["href"]
            } ?? []
    }
    
    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    
    private static func classList(_ values: String...) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension Archive {
    func addEntry(with path: String, contents text: String, compressionMethod: CompressionMethod) throws {
        let data = Data(text.utf8)
        try addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: compressionMethod
        ) { position, size in
            let start = Int(position)
            let end = Swift.min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }
}
