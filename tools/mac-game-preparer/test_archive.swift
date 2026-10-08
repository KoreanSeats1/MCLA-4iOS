import Foundation
@main struct ArchiveTests {
 static func main() throws {
  let root = URL(fileURLWithPath: CommandLine.arguments[1])
  let fm = FileManager.default
  let manifest = try JSONDecoder().decode(GameManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
  let output = try GameInput.prepare(root.appendingPathComponent("good.zip"), manifest: manifest, cancelled: {false}, progress: {_,_ in})
  try require(try Data(contentsOf: output.appendingPathComponent("movies/intro.bik")) == Data("movie".utf8), "nested movie bytes")
  print("PASS: wrapped ZIP -> correct lowercase game folder")
  try fm.removeItem(at: output)
  for name in ["traversal", "symlink", "collision", "multiple", "truncated", "patch"] {
   var rejected = false
   do { _ = try GameInput.prepare(root.appendingPathComponent(name + ".zip"), manifest: manifest, cancelled: {false}, progress: {_,_ in}) }
   catch { rejected = true }
   try require(rejected, "unsafe input must be rejected: \(name)")
   try require(!fm.fileExists(atPath: output.path), "no final output after rejection")
   try require(!(try fm.contentsOfDirectory(atPath: root.path)).contains { $0.hasPrefix(".MCLA-preparing") }, "staging cleanup")
   print("PASS: \(name) rejected and unfinished data removed")
  }
  var rejected = false
  do { _ = try GameInput.prepare(root.appendingPathComponent("good.zip"), manifest: manifest, cancelled: {true}, progress: {_,_ in}) }
  catch { rejected = true }
  try require(rejected, "cancelled archive")
  print("PASS: cancelled archive leaves no prepared folder")
 }
}
