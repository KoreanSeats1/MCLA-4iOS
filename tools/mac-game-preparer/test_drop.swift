import AppKit
import Foundation

@main struct DropTests {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("mcla-drop-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        let iso = directory.appendingPathComponent("game.ISO")
        let text = directory.appendingPathComponent("readme.txt")
        try Data().write(to: iso); try Data().write(to: text)
        try require(ISODropZone.acceptedISO([iso]) == iso, "uppercase ISO drop")
        try require(ISODropZone.acceptedISO([]) == nil, "empty drop")
        try require(ISODropZone.acceptedISO([iso, iso]) == nil, "multiple ISO drop")
        try require(ISODropZone.acceptedISO([text]) == nil, "non-ISO drop")
        try require(ISODropZone.acceptedISO([directory]) == directory, "extracted folder drop")
        try require(ISODropZone.acceptedISO([directory.appendingPathComponent("missing.iso")]) == nil, "missing file drop")
        try require(ISODropZone.acceptedISO([URL(string: "https://example.com/game.iso")!]) == nil, "remote URL drop")
        for ext in ["rar", "zip", "7z"] {
            let archive = directory.appendingPathComponent("game." + ext)
            try Data().write(to: archive)
            try require(ISODropZone.acceptedISO([archive]) == archive, "archive drop: \(ext)")
        }
        print("PASS: drag input accepts ISO, archives and extracted folders; rejects unsupported inputs")
        var ps3 = Data(repeating: 0, count: 40 * 2048)
        func putLE(_ position: Int, _ value: UInt32) {
            for i in 0..<4 { ps3[position + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
        }
        ps3[16 * 2048] = 1
        ps3.replaceSubrange((16 * 2048 + 1)..<(16 * 2048 + 6), with: Data("CD001".utf8))
        putLE(16 * 2048 + 158, 20); putLE(16 * 2048 + 166, 2048)
        var position = 20 * 2048
        for name in ["PS3_GAME", "PS3_DISC.SFB;1"] {
            let bytes = 33 + name.count + (name.count % 2 == 0 ? 1 : 0)
            ps3[position] = UInt8(bytes); ps3[position + 32] = UInt8(name.count)
            ps3.replaceSubrange((position + 33)..<(position + 33 + name.count), with: Data(name.utf8))
            position += bytes
        }
        let fixture = directory.appendingPathComponent("ps3.iso")
        try ps3.write(to: fixture)
        var rejected = false
        do { _ = try XboxDisc(fixture) }
        catch {
            try require(error.localizedDescription.contains("PlayStation 3 release"), "PS3 platform diagnosis")
            rejected = true
            print("PASS: PS3 disc metadata produces a platform-specific error")
        }
        try require(rejected, "PS3 ISO must be rejected")
        if CommandLine.arguments.count > 1 {
            let actual = URL(fileURLWithPath: CommandLine.arguments[1])
            try require(ISODropZone.acceptedISO([actual]) == actual, "supplied ISO selection")
            do { _ = try XboxDisc(actual) }
            catch {
                try require(error.localizedDescription.contains("PlayStation 3 release"), "specific PS3 diagnosis")
                print("PASS: supplied PS3 ISO rejected with platform-specific message")
                return
            }
            throw PreparationError(message: "Expected supplied PS3 ISO to be rejected")
        }
    }
}
