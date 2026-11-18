import AVFoundation
import AppKit

// usage: sheet VIDEO info | sheet VIDEO OUT.jpg START STEP COUNT COLUMNS THUMB_WIDTH
let args = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
guard let track = asset.tracks(withMediaType: .video).first else { fatalError("no video track") }
if args[2] == "info" {
    let size = track.naturalSize.applying(track.preferredTransform)
    print("duration=\(asset.duration.seconds)s size=\(abs(size.width))x\(abs(size.height)) fps=\(track.nominalFrameRate)")
    exit(0)
}
let (out, start, step, count, cols, thumbW) = (args[2], Double(args[3])!, Double(args[4])!, Int(args[5])!, Int(args[6])!, Int(args[7])!)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
gen.maximumSize = CGSize(width: thumbW, height: thumbW)
var ctx: CGContext? = nil
var thumbH = 0
let rows = Int(ceil(Double(count) / Double(cols)))
for i in 0..<count {
    let t = start + step * Double(i)
    guard t < asset.duration.seconds, let image = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) else { continue }
    if ctx == nil {
        thumbH = image.width
        ctx = CGContext(data: nil, width: image.height * cols, height: thumbH * rows, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx!, flipped: false)
    }
    let cellW = image.height
    let x = (i % cols) * cellW, y = (rows - 1 - i / cols) * thumbH
    // The phone filmed the keyboard sideways, so turn each frame clockwise to level it.
    ctx!.saveGState()
    ctx!.translateBy(x: CGFloat(x) + CGFloat(cellW) / 2, y: CGFloat(y) + CGFloat(thumbH) / 2)
    ctx!.rotate(by: -.pi / 2)
    ctx!.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
    ctx!.restoreGState()
    let label = NSAttributedString(string: String(format: " %.2fs ", t), attributes: [
        .font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.yellow, .backgroundColor: NSColor.black])
    label.draw(at: NSPoint(x: x + 4, y: y + thumbH - 24))
}
guard let result = ctx?.makeImage() else { fatalError("no frames") }
let rep = NSBitmapImageRep(cgImage: result)
try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
