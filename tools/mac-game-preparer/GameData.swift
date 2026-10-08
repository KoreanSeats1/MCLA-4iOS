import Foundation
import CryptoKit

struct PreparationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw PreparationError(message: message) }
}
struct GameManifest: Decodable {
    let mediaId: String
    let baselineDefaultXexSha256: String
    let requiredFiles: [String]
    let compatibleExecutables: [CompatibleExecutable]?
    init(mediaId: String, baselineDefaultXexSha256: String, requiredFiles: [String], compatibleExecutables: [CompatibleExecutable]? = nil) {
        self.mediaId = mediaId; self.baselineDefaultXexSha256 = baselineDefaultXexSha256
        self.requiredFiles = requiredFiles; self.compatibleExecutables = compatibleExecutables
    }
    func accepts(media: String, hash: String) -> Bool {
        (media == mediaId.uppercased() && hash == baselineDefaultXexSha256) ||
        (compatibleExecutables ?? []).contains { $0.mediaId.uppercased() == media && $0.defaultXexSha256 == hash }
    }
}
struct CompatibleExecutable: Decodable {
    let mediaId: String
    let defaultXexSha256: String
}
struct DiscEntry {
    let path: String
    let offset: UInt64
    let size: UInt64
    let directory: Bool
}
final class XboxDisc {
    let handle: FileHandle
    let size: UInt64
    var entries: [DiscEntry] = []
    var partition: UInt64 = 0
    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = try handle.seekToEnd()
        do { try parse() } catch { try? handle.close(); throw error }
    }
    deinit { try? handle.close() }
    func read(_ offset: UInt64, _ count: Int) throws -> Data {
        try require(count >= 0 && offset <= size && UInt64(count) <= size - offset, "The ISO is truncated or contains an out-of-bounds entry.")
        try handle.seek(toOffset: offset)
        let bytes = try handle.read(upToCount: count) ?? Data()
        try require(bytes.count == count, "Could not read the complete ISO data.")
        return bytes
    }
    func parse() throws {
        let magic = Data("MICROSOFT*XBOX*MEDIA".utf8)
        var found = false
        for candidate: UInt64 in [0, 0xFB20, 0x20600, 0x2080000, 0xFD90000] {
            if candidate + 65536 + 2048 <= size,
               try read(candidate + 65536, 20) == magic,
               try read(candidate + 65536 + 2028, 20) == magic {
                partition = candidate; found = true; break
            }
        }
        if !found, try isPlayStationDisc() {
            throw PreparationError(message: "This ISO is the PlayStation 3 release: it contains PS3_GAME and PS3 disc metadata. MCLA 4iOS requires Midnight Club: Los Angeles — Complete Edition for Xbox 360 (USA / NTSC-U). A PS3 ISO cannot be converted into the compatible Xbox game files by extraction. Choose a raw Xbox 360 disc ISO.")
        }
        try require(found, "This is not a recognized Xbox 360 XDVDFS disc ISO. Choose your raw Xbox 360 Complete Edition (USA / NTSC-U) rip.")
        let root = try read(partition + 65536 + 20, 8)
        var pending: [(UInt64, UInt64, Int, String)] = [(partition + UInt64(root.le32(0)) * 2048, UInt64(root.le32(4)), 0, "")]
        var visited = Set<String>()
        var paths = Set<String>()
        while let (base, length, node, prefix) = pending.popLast() {
            try require(visited.count < 500000 && prefix.count < 4096, "The ISO directory tree is too large.")
            try require(length >= 14 && length <= 32 * 1024 * 1024 && base <= size && length <= size - base, "Invalid ISO directory extent.")
            try require(node >= 0 && UInt64(node) + 14 <= length, "Invalid ISO directory pointer.")
            try require(visited.insert("\(base):\(node)").inserted, "The ISO contains a cyclic or shared directory tree.")
            let header = try read(base + UInt64(node), 14)
            let n = Int(header[13])
            try require(n > 0 && UInt64(node + 14 + n) <= length, "Invalid ISO filename length.")
            let raw = try read(base + UInt64(node + 14), n)
            guard let name = String(data: raw, encoding: .ascii) else { throw PreparationError(message: "Unsupported non-ASCII ISO filename.") }
            try require(![".", ".."].contains(name) && !name.contains("/") && !name.contains("\\") && !name.contains(":") && !name.contains("\0"), "The ISO contains an unsafe filename.")
            let path = prefix + name.lowercased()
            try require(paths.insert(path).inserted, "The ISO contains duplicate filenames.")
            for child in [header.le16(0), header.le16(2)] where child != 0 {
                pending.append((base, length, Int(child) * 4, prefix))
            }
            let offset = partition + UInt64(header.le32(4)) * 2048
            let bytes = UInt64(header.le32(8))
            try require(offset <= size && bytes <= size - offset, "The ISO contains a truncated file.")
            let directory = header[12] & 0x10 != 0
            entries.append(DiscEntry(path: path, offset: offset, size: bytes, directory: directory))
            if directory && bytes > 0 { pending.append((offset, bytes, 0, path + "/")) }
        }
    }
    private func isPlayStationDisc() throws -> Bool {
        guard size >= 17 * 2048 else { return false }
        let descriptor = try read(16 * 2048, 2048)
        guard descriptor[0] == 1 && descriptor.subdata(in: 1..<6) == Data("CD001".utf8) else { return false }
        let base = UInt64(descriptor.le32(158)) * 2048
        let length = Int(descriptor.le32(166))
        guard length >= 34 && length <= 16 * 1024 * 1024 && base <= size && UInt64(length) <= size - base else { return false }
        let directory = try read(base, length)
        var position = 0
        var names = Set<String>()
        while position < directory.count {
            let bytes = Int(directory[position])
            if bytes == 0 { position = (position / 2048 + 1) * 2048; continue }
            guard bytes >= 34 && position + bytes <= directory.count else { return false }
            let nameLength = Int(directory[position + 32])
            guard nameLength <= bytes - 33 else { return false }
            let name = String(data: directory.subdata(in: (position + 33)..<(position + 33 + nameLength)), encoding: .ascii) ?? ""
            names.insert(name.uppercased())
            position += bytes
        }
        return names.contains("PS3_GAME") && names.contains("PS3_DISC.SFB;1")
    }
    func validate(_ manifest: GameManifest) throws -> String {
        try require(!entries.contains { $0.path == "default.xexp" }, "This input includes an unverified title-update patch. This iOS build does not need a title update.")
        for name in manifest.requiredFiles {
            try require(entries.contains { $0.path == name && !$0.directory && $0.size > 0 }, "This ISO is missing \(name). Use the Xbox 360 Complete Edition disc.")
        }
        let xex = entries.first { $0.path == "default.xex" }!
        let header = try read(xex.offset, Int(min(xex.size, 1024 * 1024)))
        try require(header.count >= 24 && header.prefix(4) == Data("XEX2".utf8), "default.xex is not an Xbox 360 executable.")
        let count = Int(header.be32(20))
        try require(count <= (header.count - 24) / 8, "Invalid executable optional headers.")
        var execution: Int?
        for i in 0..<count where header.be32(24 + i * 8) == 0x40006 {
            execution = Int(header.be32(28 + i * 8))
        }
        guard let execution else { throw PreparationError(message: "The executable has no Xbox title information.") }
        try require(execution <= header.count - 24, "Invalid executable title information.")
        let title = header.be32(execution + 12)
        let media = String(format: "%08X", header.be32(execution))
        try require(title == 0x545407F8, "This disc is for a different game (title \(String(format: "%08X", title))).")
        var hash = SHA256()
        var done: UInt64 = 0
        while done < xex.size {
            let chunk = try read(xex.offset + done, Int(min(4 * 1024 * 1024, xex.size - done)))
            hash.update(data: chunk); done += UInt64(chunk.count)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        try require(manifest.accepts(media: media, hash: digest), "This MCLA executable has not been verified for this iOS build. Media ID: \(media). SHA-256: \(digest). Matching the game name alone is not enough to verify compatibility.")
        return digest
    }
    func extract(beside directory: URL, manifest: GameManifest, cancelled: () -> Bool,
                 progress: (Double, String) -> Void) throws -> URL {
        let fm = FileManager.default
        let output = directory.appendingPathComponent("MCLA_Game_Files", isDirectory: true)
        try require(!fm.fileExists(atPath: output.path), "MCLA_Game_Files already exists here. Move it aside or choose a different folder; existing game data will not be overwritten.")
        progress(0, "Checking compatibility with MCLA 4iOS…")
        let hash = try validate(manifest)
        let identity = try GameInput.xexDetails(read(entries.first { $0.path == "default.xex" }!.offset, Int(entries.first { $0.path == "default.xex" }!.size)), manifest: manifest)
        try require(!cancelled(), "Preparation cancelled.")
        let total = entries.filter { !$0.directory }.reduce(UInt64(0)) { $0 + $1.size }
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let available = values.volumeAvailableCapacity {
            try require(UInt64(max(0, available)) >= total + 256 * 1024 * 1024, "Not enough free space. Extraction needs about \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)) plus 256 MB.")
        }
        let stage = directory.appendingPathComponent(".MCLA-preparing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? fm.removeItem(at: stage) } }
        var copied: UInt64 = 0
        for entry in entries {
            try require(!cancelled(), "Preparation cancelled.")
            let target = stage.appendingPathComponent(entry.path, isDirectory: entry.directory)
            if entry.directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true); continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try require(fm.createFile(atPath: target.path, contents: nil), "Could not create \(entry.path).")
            let writer = try FileHandle(forWritingTo: target)
            do {
                var offset: UInt64 = 0
                while offset < entry.size {
                    try require(!cancelled(), "Preparation cancelled.")
                    let chunk = try read(entry.offset + offset, Int(min(4 * 1024 * 1024, entry.size - offset)))
                    try writer.write(contentsOf: chunk)
                    offset += UInt64(chunk.count); copied += UInt64(chunk.count)
                    progress(Double(copied) / Double(max(1, total)), entry.path)
                }
                try writer.synchronize(); try writer.close()
            } catch { try? writer.close(); throw error }
        }
        // Verify the copied executable, not just the source disc.
        let copiedHash = SHA256.hash(data: try Data(contentsOf: stage.appendingPathComponent("default.xex"))).map { String(format: "%02x", $0) }.joined()
        try require(copiedHash == hash, "The extracted executable failed verification.")
        let report = "MCLA 4iOS game-data preparation\nTitle: 545407F8\nMedia: \(identity.0)\nVersion: \(identity.1)\ndefault.xex SHA-256: \(hash)\nFiles: \(entries.filter { !$0.directory }.count)\nNo title update applied.\n\nCopy MCLA_Game_Files into Files → On My iPhone/iPad → MCLA.\nKeep the iOS app closed during transfer. Do not add another Documents folder.\nCompatibility matches the recorded executable baseline; this does not verify gameplay.\n"
        try report.write(to: stage.appendingPathComponent("PREPARATION.txt"), atomically: true, encoding: .utf8)
        try require(!cancelled(), "Preparation cancelled.")
        try fm.moveItem(at: stage, to: output)
        complete = true
        return output
    }
}
extension Data {
    func le16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func le32(_ i: Int) -> UInt32 { UInt32(le16(i)) | UInt32(le16(i + 2)) << 16 }
    func be32(_ i: Int) -> UInt32 { UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3]) }
}
