// Net.swift — the app's own requests to the internet: the AI in the cloud when that's
// chosen, radio stations, podcasts and audiobooks, Wikipedia and the dictionary, the
// barcode database, and the update check. One session for all of them that keeps nothing
// (no cookies, no cache on disk), and a size limit on every answer, so a server that sends
// far too much can't fill the Mac's memory.

import Foundation

enum Net {
    struct TooLarge: Error {}

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        // A whole answer within five minutes, however slowly it trickles in.
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    /// Plenty for an answer in JSON (a search, a definition, an AI's reply).
    static let jsonLimit = 4_000_000
    /// Plenty for a podcast's or audiobook's list of episodes.
    static let feedLimit = 16_000_000
    /// Plenty for the app's installer.
    static let installerLimit = 400_000_000

    /// The answer to a request, as long as it's no bigger than `limit` bytes.
    static func data(for request: URLRequest, limit: Int = jsonLimit) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        // What the server says it will send, then what it really sends.
        guard response.expectedContentLength <= Int64(limit) else { throw TooLarge() }
        var received = [UInt8]()
        if response.expectedContentLength > 0 { received.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            received.append(byte)
            if received.count > limit { throw TooLarge() }
        }
        return (Data(received), response)
    }

    static func data(from url: URL, limit: Int = jsonLimit) async throws -> Data {
        try await data(for: URLRequest(url: url), limit: limit).0
    }
}

/// One small file out of a xar archive, which is what an installer package is: read in
/// place, without unpacking the package or running another program.
enum Xar {
    static func file(named name: String, in archive: URL, limit: Int = 1 << 20) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return nil }
        defer { try? handle.close() }
        // The header: "xar!", its own size, a version, then the size of the table of
        // contents as stored (compressed) and unpacked. Numbers are big-endian.
        guard let header = try? handle.read(upToCount: 28), header.count == 28,
              header.prefix(4).elementsEqual("xar!".utf8) else { return nil }
        func number(_ range: Range<Int>) -> UInt64 {
            header[header.startIndex + range.lowerBound ..< header.startIndex + range.upperBound].reduce(0) { $0 << 8 | UInt64($1) }
        }
        let headerSize = number(4..<6), tocStored = number(8..<16), tocSize = number(16..<24)
        guard headerSize >= 28, tocStored > 2, tocStored <= 4 << 20, tocSize > 0, tocSize <= 32 << 20,
              (try? handle.seek(toOffset: headerSize)) != nil,
              let packed = try? handle.read(upToCount: Int(tocStored)), packed.count == Int(tocStored),
              let toc = inflate(packed, size: Int(tocSize)),
              let document = try? XMLDocument(data: toc, options: [.nodeLoadExternalEntitiesNever]),
              let entry = try? document.nodes(forXPath: "/xar/toc/file[name='\(name)']/data").first as? XMLElement else { return nil }
        func value(_ child: String) -> UInt64? { entry.elements(forName: child).first?.stringValue.flatMap { UInt64($0) } }
        // Where it is (counted from the end of the table of contents), how much is stored,
        // and how big it is unpacked.
        guard let offset = value("offset"), let length = value("length"), let size = value("size"),
              length > 0, length <= UInt64(limit), size <= UInt64(limit),
              (try? handle.seek(toOffset: headerSize + tocStored + offset)) != nil,
              let stored = try? handle.read(upToCount: Int(length)), stored.count == Int(length) else { return nil }
        let style = entry.elements(forName: "encoding").first?.attribute(forName: "style")?.stringValue ?? ""
        switch style {
        case "application/octet-stream": return stored
        case "application/x-gzip": return inflate(stored, size: Int(size))
        default: return nil
        }
    }

    /// Unpacks a zlib stream (two bytes of header, then the data) into at most `size` bytes.
    private static func inflate(_ data: Data, size: Int) -> Data? {
        guard data.count > 2, size > 0 else { return nil }
        guard let unpacked = try? (Data(data.dropFirst(2)) as NSData).decompressed(using: .zlib) as Data,
              unpacked.count <= size else { return nil }
        return unpacked
    }
}
