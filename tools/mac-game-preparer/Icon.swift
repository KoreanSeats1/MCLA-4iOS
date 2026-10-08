import AppKit
let folder = CommandLine.arguments[1]
var chunks = Data()
func sizeWord(_ value: Int) -> Data {
    var word = UInt32(value).bigEndian
    return withUnsafeBytes(of: &word) { Data($0) }
}
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s = CGFloat(size) / 1024
    NSAffineTransform(transform: AffineTransform(scale: s)).concat()
    let rounded = NSBezierPath(roundedRect: NSRect(x: 45,y: 45,width: 934,height: 934), xRadius: 205,yRadius: 205)
    NSColor(calibratedRed: 0.025,green: 0.04,blue: 0.10,alpha: 1).setFill(); rounded.fill()
    rounded.addClip()
    let road = NSBezierPath(); road.move(to: NSPoint(x: 125,y: 0)); road.line(to: NSPoint(x: 465,y: 740)); road.line(to: NSPoint(x: 559,y: 740)); road.line(to: NSPoint(x: 899,y: 0)); road.close()
    NSColor(calibratedRed: 0.09,green: 0.13,blue: 0.22,alpha: 1).setFill(); road.fill()
    let cyan = NSColor(calibratedRed: 0.13,green: 0.85,blue: 0.95,alpha: 1)
    cyan.setStroke()
    for x in [CGFloat(155),CGFloat(869)] {
        let edge = NSBezierPath(); edge.move(to: NSPoint(x: x,y: 0)); edge.line(to: NSPoint(x: x < 512 ? 475 : 549,y: 735)); edge.lineWidth = 14; edge.stroke()
    }
    NSColor.white.withAlphaComponent(0.8).setStroke()
    for (y, width) in [(CGFloat(100),CGFloat(20)),(280,15),(440,10)] {
        let line = NSBezierPath(); line.move(to: NSPoint(x: 512,y: y)); line.line(to: NSPoint(x: 512,y: y+85)); line.lineWidth = width; line.stroke()
    }
    let disc = NSBezierPath(ovalIn: NSRect(x: 275,y: 365,width: 474,height: 474))
    NSColor(calibratedWhite: 0.83,alpha: 1).setFill(); disc.fill()
    for diameter in [CGFloat(400),CGFloat(340)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: 512-diameter/2,y: 602-diameter/2,width: diameter,height: diameter)); NSColor(calibratedWhite: 0.5,alpha: 0.4).setStroke(); ring.lineWidth = 5; ring.stroke()
    }
    NSColor(calibratedRed: 0.04,green: 0.07,blue: 0.14,alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 455,y: 545,width: 114,height: 114)).fill()
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 670,y: 655)); arrow.line(to: NSPoint(x: 670,y: 460)); arrow.line(to: NSPoint(x: 602,y: 460)); arrow.line(to: NSPoint(x: 735,y: 307)); arrow.line(to: NSPoint(x: 868,y: 460)); arrow.line(to: NSPoint(x: 800,y: 460)); arrow.line(to: NSPoint(x: 800,y: 655)); arrow.close()
    cyan.setFill(); arrow.fill()
    if size >= 128 {
        let text = "MCLA" as NSString
        text.draw(at: NSPoint(x: 330,y: 160), withAttributes: [.font:NSFont.systemFont(ofSize: 115,weight:.heavy),.foregroundColor:NSColor.white])
    }
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    let types = ["icon_16x16":"icp4", "icon_32x32":"icp5", "icon_32x32@2x":"icp6", "icon_128x128":"ic07", "icon_256x256":"ic08", "icon_512x512":"ic09", "icon_512x512@2x":"ic10"]
    if let type = types[name] { chunks.append(Data(type.utf8)); chunks.append(sizeWord(png.count + 8)); chunks.append(png) }
}

var icns = Data("icns".utf8)
icns.append(sizeWord(chunks.count + 8)); icns.append(chunks)
try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
