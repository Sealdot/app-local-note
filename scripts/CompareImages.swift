import AppKit
import Foundation

@main
private enum CompareImages {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw NSError(
                domain: "CompareImages",
                code: 64,
                userInfo: [NSLocalizedDescriptionKey: "usage: CompareImages SOURCE IMPLEMENTATION OUTPUT"]
            )
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let implementationURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
        guard let source = NSImage(contentsOf: sourceURL),
              let implementation = NSImage(contentsOf: implementationURL) else {
            throw NSError(domain: "CompareImages", code: 1)
        }

        let panelSize = NSSize(width: 880, height: 1120)
        let gap: CGFloat = 24
        let outputSize = NSSize(width: panelSize.width * 2 + gap, height: panelSize.height)
        let output = NSImage(size: outputSize)
        output.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: outputSize).fill()
        source.draw(
            in: NSRect(origin: .zero, size: panelSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        implementation.draw(
            in: NSRect(x: panelSize.width + gap, y: 0, width: panelSize.width, height: panelSize.height),
            from: NSRect(origin: .zero, size: implementation.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CompareImages", code: 2)
        }
        try png.write(to: outputURL, options: .atomic)
    }
}
