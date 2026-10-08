import Foundation
import CryptoKit

@_silgen_name("archive_read_new") private func archiveNew() -> OpaquePointer?
@_silgen_name("archive_read_support_filter_all") private func archiveFilters(_ a: OpaquePointer) -> Int32
@_silgen_name("archive_read_support_format_all") private func archiveFormats(_ a: OpaquePointer) -> Int32
@_silgen_name("archive_read_open_filename") private func archiveOpen(_ a: OpaquePointer, _ path: UnsafePointer<CChar>, _ block: Int) -> Int32
@_silgen_name("archive_read_next_header") private func archiveNext(_ a: OpaquePointer, _ entry: UnsafeMutablePointer<OpaquePointer?>) -> Int32
@_silgen_name("archive_entry_pathname") private func archivePath(_ e: OpaquePointer) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_filetype") private func archiveType(_ e: OpaquePointer) -> UInt32
@_silgen_name("archive_entry_size") private func archiveSize(_ e: OpaquePointer) -> Int64
@_silgen_name("archive_entry_symlink") private func archiveSymlink(_ e: OpaquePointer) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_hardlink") private func archiveHardlink(_ e: OpaquePointer) -> UnsafePointer<CChar>?
@_silgen_name("archive_read_data") private func archiveData(_ a: OpaquePointer, _ buffer: UnsafeMutableRawPointer, _ size: Int) -> Int
@_silgen_name("archive_error_string") private func archiveError(_ a: OpaquePointer) -> UnsafePointer<CChar>?
@_silgen_name("archive_read_free") private func archiveFree(_ a: OpaquePointer) -> Int32

struct GameInput {
    static func selected(_ urls: [URL]) -> URL? {
        guard urls.count == 1, let url = urls.first, url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { return nil }
        if values.isDirectory == true { return url }
        return values.isRegularFile == true && ["iso", "rar", "zip", "7z"].contains(url.pathExtension.lowercased()) ? url : nil
    }
    static func safePath(_ path: String) throws -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        try require(!path.hasPrefix("/") && !path.contains("\\") && !path.contains(":") && !path.contains("\0") && !parts.contains(".."), "The input contains an unsafe file path.")
        let clean = parts.filter { !$0.isEmpty && $0 != "." }.joined(separator: "/").lowercased()
        try require(!clean.isEmpty && clean.count < 4096, "Invalid input filename.")
        return clean
    }
    static func xexDetails(_ data: Data, manifest: GameManifest) throws -> (String, String, String) {
        try require(data.count >= 24 && data.prefix(4) == Data("XEX2".utf8), "default.xex is not an Xbox 360 executable.")
        let count = Int(data.be32(20))
        try require(count <= (data.count - 24) / 8, "Invalid Xbox executable headers.")
        var at: Int?
        for i in 0..<count where data.be32(24 + i * 8) == 0x40006 { at = Int(data.be32(28 + i * 8)) }
        guard let at else { throw PreparationError(message: "The executable has no title information.") }
        try require(at <= data.count - 24 && data.be32(at + 12) == 0x545407F8, "This folder is not Midnight Club: Los Angeles for Xbox 360.")
        let media = String(format: "%08X", data.be32(at))
        let value = data.be32(at + 4)
        let version = "\(value >> 28).\((value >> 24) & 15).\((value >> 8) & 65535).\(value & 255)"
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try require(manifest.accepts(media: media, hash: hash), "This MCLA executable has not been verified for this iOS build. Media ID: \(media), version: \(version). A title update must match this disc and the iOS app’s compiled game code; the game name alone is not sufficient.")
        return (media, version, hash)
    }
    static func unpack(_ source: URL, into target: URL, cancelled: () -> Bool, progress: (Double, String) -> Void) throws {
        guard let archive = archiveNew() else { throw PreparationError(message: "Could not initialize the archive reader.") }
        defer { _ = archiveFree(archive) }
        _ = archiveFilters(archive); _ = archiveFormats(archive)
        func check(_ success: Bool) throws {
            let detail = archiveError(archive).map { String(cString: $0) } ?? "Unreadable archive."
            try require(success, "Could not unpack the archive: \(detail)")
        }
        try check(source.path.withCString { archiveOpen(archive, $0, 1024 * 1024) } == 0)
        let fm = FileManager.default
        var names = Set<String>(); var files = 0
        var buffer = [UInt8](repeating: 0, count: 4 * 1024 * 1024)
        while true {
            try require(!cancelled(), "Preparation cancelled.")
            var entry: OpaquePointer?
            let status = archiveNext(archive, &entry)
            if status == 1 { break }
            try check(status == 0)
            guard let entry, let raw = archivePath(entry) else { throw PreparationError(message: "Archive entry has no filename.") }
            try require(archiveSymlink(entry) == nil && archiveHardlink(entry) == nil, "Archive links are not supported.")
            let path = try safePath(String(cString: raw))
            let type = archiveType(entry)
            try require(type == 0o100000 || type == 0o040000, "Archive contains a special file.")
            files += 1; try require(files <= 500000 && names.insert(path).inserted, "Archive contains duplicate paths or too many files.")
            let output = target.appendingPathComponent(path)
            progress(-1, "Unpacking · \(path)")
            if type == 0o040000 { try fm.createDirectory(at: output, withIntermediateDirectories: true); continue }
            let size = archiveSize(entry)
            try require(size >= 0, "Archive file size is unknown.")
            let free = try target.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
            try require(size <= Int64(free) - 256 * 1024 * 1024, "Not enough space to unpack \(path).")
            try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try require(fm.createFile(atPath: output.path, contents: nil), "Could not create \(path).")
            let writer = try FileHandle(forWritingTo: output)
            var written: Int64 = 0
            do {
                while true {
                    try require(!cancelled(), "Preparation cancelled.")
                    let count = buffer.withUnsafeMutableBytes { archiveData(archive, $0.baseAddress!, $0.count) }
                    try check(count >= 0)
                    if count == 0 { break }
                    written += Int64(count); try require(written <= size, "Archive file exceeds its declared size.")
                    try writer.write(contentsOf: Data(buffer.prefix(count)))
                }
                try require(written == size, "Archive is truncated.")
                try writer.close()
            } catch { try? writer.close(); throw error }
        }
    }
    static func prepare(_ source: URL, manifest: GameManifest, cancelled: () -> Bool, progress: (Double, String) -> Void) throws -> URL {
        let fm = FileManager.default
        let parent = source.deletingLastPathComponent()
        let output = parent.appendingPathComponent("MCLA_Game_Files", isDirectory: true)
        try require(!fm.fileExists(atPath: output.path), "MCLA_Game_Files already exists here. Move it aside first; existing data will not be overwritten.")
        if source.pathExtension.lowercased() == "iso" { return try XboxDisc(source).extract(beside: parent, manifest: manifest, cancelled: cancelled, progress: progress) }
        let stage = parent.appendingPathComponent(".MCLA-preparing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? fm.removeItem(at: stage) } }
        let directory = (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        if directory {
            try copy(source, into: stage, cancelled: cancelled, progress: progress)
        } else {
            try unpack(source, into: stage, cancelled: cancelled, progress: progress)
        }
        // Allow a direct folder or the single game folder commonly wrapped inside an archive.
        let children = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: [.isDirectoryKey])
        let candidates = [stage] + children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let roots = candidates.filter { fm.fileExists(atPath: $0.appendingPathComponent("default.xex").path) }
        try require(roots.count == 1, "The input must contain one extracted Xbox game folder with default.xex directly inside it. If the archive contains an ISO, unpack it and drop that ISO instead.")
        let game = roots[0]
        for name in manifest.requiredFiles {
            let url = game.appendingPathComponent(name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            try require(values.isRegularFile == true && (values.fileSize ?? 0) > 0, "Missing required game file: \(name).")
        }
        try require(!fm.fileExists(atPath: game.appendingPathComponent("default.xexp").path), "This folder includes an unverified title-update patch. Use the original disc files; this iOS build does not need a title update.")
        let executable = game.appendingPathComponent("default.xex")
        let executableSize = try executable.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try require(executableSize <= 128 * 1024 * 1024, "The executable is unexpectedly large.")
        let details = try xexDetails(Data(contentsOf: executable), manifest: manifest)
        let report = "MCLA 4iOS prepared game files\nMedia ID: \(details.0)\nVersion: \(details.1)\ndefault.xex SHA-256: \(details.2)\nNo title update applied.\nCopy this entire MCLA_Game_Files folder into Files → On My iPhone/iPad → MCLA.\n"
        try report.write(to: game.appendingPathComponent("PREPARATION.txt"), atomically: true, encoding: .utf8)
        try require(!cancelled(), "Preparation cancelled.")
        try fm.moveItem(at: game, to: output)
        if game != stage { try? fm.removeItem(at: stage) }
        complete = true; return output
    }
    static func copy(_ source: URL, into target: URL, cancelled: () -> Bool, progress: (Double, String) -> Void) throws {
        let fm = FileManager.default
        var enumerationError: Error?
        guard let enumeration = fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw PreparationError(message: "Could not read the game folder.") }
        var names = Set<String>()
        for case let url as URL in enumeration {
            try require(!cancelled(), "Preparation cancelled.")
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            try require(values.isSymbolicLink != true && (values.isDirectory == true || values.isRegularFile == true), "Game folders must not contain links or special files.")
            let path = try safePath(String(url.path.dropFirst(source.path.count + 1)))
            try require(names.count < 500000 && names.insert(path).inserted, "Duplicate paths in the game folder.")
            let output = target.appendingPathComponent(path)
            progress(-1, "Copying · \(path)")
            if values.isDirectory == true { try fm.createDirectory(at: output, withIntermediateDirectories: true) }
            else { try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true); try fm.copyItem(at: url, to: output) }
        }
        if let error = enumerationError { throw error }
    }
}
