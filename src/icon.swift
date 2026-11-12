import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let outer = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.40, blue: 0.34, alpha: 1),
               ending: NSColor(srgbRed: 0.06, green: 0.24, blue: 0.22, alpha: 1))!.draw(in: outer, angle: -90)
    let paper = NSBezierPath(roundedRect: NSRect(x: 218, y: 191, width: 590, height: 650), xRadius: 52, yRadius: 52)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 1, green: 0.96, blue: 0.82, alpha: 1).setFill()
    paper.fill()
    NSGraphicsContext.restoreGraphicsState()
    let text = "文" as NSString
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = NSFont(name: "PingFangSC-Semibold", size: 370) ?? NSFont.systemFont(ofSize: 370, weight: .semibold)
    text.draw(in: NSRect(x: 232, y: 294, width: 560, height: 455), withAttributes: [
        .font: font, .foregroundColor: NSColor(srgbRed: 0.12, green: 0.32, blue: 0.27, alpha: 1),
        .paragraphStyle: paragraph
    ])
    NSColor(srgbRed: 0.77, green: 0.66, blue: 0.38, alpha: 0.55).setFill()
    NSBezierPath(roundedRect: NSRect(x: 337, y: 287, width: 350, height: 15), xRadius: 7, yRadius: 7).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
    let name: String
    switch pixels {
    case 16: name = "icon_16x16.png"
    case 32: name = "icon_16x16@2x.png"
    case 64: name = "icon_32x32@2x.png"
    case 128: name = "icon_128x128.png"
    case 256: name = "icon_128x128@2x.png"
    case 512: name = "icon_256x256@2x.png"
    default: name = "icon_512x512@2x.png"
    }
    try png.write(to: directory.appendingPathComponent(name))
}
