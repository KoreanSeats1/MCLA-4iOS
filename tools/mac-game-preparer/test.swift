import Foundation
import CryptoKit

@main struct Tests {
 static func main() throws {
    let fm = FileManager.default
    let temporary = fm.temporaryDirectory.appendingPathComponent("mcla-prep-test-\(UUID().uuidString)")
    try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: temporary) }
    func putLE(_ data: inout Data, _ index: Int, _ value: UInt32, _ bytes: Int = 4) {
        for i in 0..<bytes { data[index+i] = UInt8(truncatingIfNeeded: value >> (i*8)) }
    }
    func putBE(_ data: inout Data, _ index: Int, _ value: UInt32) {
        for i in 0..<4 { data[index+i] = UInt8(truncatingIfNeeded: value >> ((3-i)*8)) }
    }
    var xex = Data(repeating: 0, count: 128)
    xex.replaceSubrange(0..<4, with: Data("XEX2".utf8))
    putBE(&xex,20,1); putBE(&xex,24,0x40006); putBE(&xex,28,64)
    putBE(&xex,64,0x5940C9DB); putBE(&xex,76,0x545407F8)
    let hash = SHA256.hash(data: xex).map { String(format: "%02x", $0) }.joined()
    let manifest = GameManifest(mediaId: "5940C9DB", baselineDefaultXexSha256: hash, requiredFiles: ["default.xex","xarchive_audio.rpf","xarchive_audlo.rpf","xarchive_cache.rpf","xarchive_music.rpf"])
    var iso = Data(repeating: 0, count: 48 * 2048)
    let magic = Data("MICROSOFT*XBOX*MEDIA".utf8)
    iso.replaceSubrange(65536..<65556, with: magic)
    iso.replaceSubrange((65536+2028)..<(65536+2048), with: magic)
    putLE(&iso,65556,34); putLE(&iso,65560,2048)
    let names = manifest.requiredFiles + ["MOVIES", "empty.bin"]
    for (i, name) in names.enumerated() {
        let base = 34*2048+i*64
        if i+1 < names.count { putLE(&iso,base+2,UInt32((i+1)*16),2) }
        putLE(&iso,base+4,UInt32(36+i))
        let payload = i == 0 ? xex : Data("data".utf8)
        putLE(&iso,base+8,UInt32(i == 5 ? 2048 : i == 6 ? 0 : payload.count))
        iso[base+12] = i == 5 ? 0x10 : 0
        iso[base+13] = UInt8(name.count)
        iso.replaceSubrange((base+14)..<(base+14+name.count),with: Data(name.utf8))
        if i != 5 { iso.replaceSubrange(((36+i)*2048)..<((36+i)*2048+payload.count),with: payload) }
    }
    let movie = 41*2048
    putLE(&iso,movie+4,44); putLE(&iso,movie+8,4); iso[movie+13] = 9
    iso.replaceSubrange((movie+14)..<(movie+23),with:Data("INTRO.BIK".utf8))
    iso.replaceSubrange((44*2048)..<(44*2048+4),with:Data("bink".utf8))
    let file = temporary.appendingPathComponent("test.iso")
    try iso.write(to: file)
    let disc = try XboxDisc(file)
    try require(try disc.validate(manifest) == hash, "fixture validation")
    let out = try disc.extract(beside: temporary,manifest:manifest,cancelled:{false},progress:{_,_ in})
    try require(try Data(contentsOf: out.appendingPathComponent("movies/intro.bik")) == Data("bink".utf8), "nested extraction")
    try require(try Data(contentsOf: out.appendingPathComponent("default.xex")) == xex, "executable extraction")
    func rejects(_ name: String, _ work: () throws -> Void) throws {
        do { try work() } catch { print("PASS: \(name)"); return }
        throw PreparationError(message: "Expected rejection: \(name)")
    }
    try rejects("existing destination preserved") { _ = try disc.extract(beside:temporary,manifest:manifest,cancelled:{false},progress:{_,_ in}) }
    try fm.removeItem(at: out)
    var chunks = 0
    try rejects("mid-extraction cancellation") { _ = try disc.extract(beside:temporary,manifest:manifest,cancelled:{ chunks > 1 },progress:{_,_ in chunks += 1}) }
    try require(!(try fm.contentsOfDirectory(atPath: temporary.path)).contains { $0.hasPrefix(".MCLA") || $0 == "MCLA_Game_Files" }, "cancel cleanup")
    let mismatch = GameManifest(mediaId:"5940C9DB",baselineDefaultXexSha256:String(repeating:"0",count:64),requiredFiles:manifest.requiredFiles)
    try rejects("incompatible executable hash") { _ = try disc.validate(mismatch) }
    var damaged = iso; putLE(&damaged,34*2048+2,16,2); putLE(&damaged,34*2048+64+2,16,2)
    try damaged.write(to:file)
    try rejects("cyclic directory") { _ = try XboxDisc(file) }
    damaged = iso; damaged[34*2048+14] = 47; try damaged.write(to:file)
    try rejects("path traversal") { _ = try XboxDisc(file) }
    damaged = iso; putLE(&damaged,34*2048+4,100000); try damaged.write(to:file)
    try rejects("out-of-bounds extent") { _ = try XboxDisc(file) }
    damaged = iso; putBE(&damaged,36*2048+76,0x12345678); try damaged.write(to:file)
    try rejects("wrong game") { _ = try XboxDisc(file).validate(manifest) }
    damaged = iso; putBE(&damaged,36*2048+64,0x12345678); try damaged.write(to:file)
    try rejects("wrong media") { _ = try XboxDisc(file).validate(manifest) }
    try iso.prefix(100).write(to:file)
    try rejects("truncated ISO") { _ = try XboxDisc(file) }
    for offset: UInt64 in [0xFB20, 0x20600, 0x2080000, 0xFD90000] {
        let raw = temporary.appendingPathComponent("raw-\(offset).iso")
        try require(fm.createFile(atPath: raw.path, contents: nil), "raw fixture creation")
        let writer = try FileHandle(forWritingTo: raw)
        try writer.seek(toOffset: offset); try writer.write(contentsOf: iso); try writer.close()
        let rawDisc = try XboxDisc(raw)
        try require(try rawDisc.validate(manifest) == hash, "raw disc compatibility")
        try require(rawDisc.entries.count == disc.entries.count, "raw disc file listing")
        print("PASS: raw disc partition offset \(String(offset, radix: 16))")
    }
    print("PASS: compatible disc, nested files, lowercase filenames, and exact extracted bytes")
 }
}
