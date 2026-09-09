import AppKit
import QuartzCore
import SwiftUI

/// Fixed character cells sample a slowly travelling, periodic landscape.
/// Only character/color values change; the text grid never translates.
enum AmbientLandscape {
    static let columns = 160
    static let rows = 72
    static let cell = 6
    static let line = 10
    static let width = columns * cell
    static let height = rows * line
    static let size = CGSize(width: width, height: height)
    static let frameInterval = 1.0 / 8.0
    static let loopDuration = 180.0
    static let glyphs = [Array(" . .:"), Array(" .:;:"), Array(":;+*+")]

    static func ridge(_ layer: Int, at x: Double) -> Double {
        let phase = x * 2 * Double.pi
        switch layer {
        case 0: return 0.47 + 0.10 * sin(phase * 2 + 0.6) + 0.035 * sin(phase * 5)
        case 1: return 0.66 + 0.10 * sin(phase * 2 + 2.2) + 0.025 * cos(phase * 6)
        default: return 0.87 + 0.12 * sin(phase - 0.8) + 0.025 * sin(phase * 4)
        }
    }

    static func shouldAnimate(visible: Bool, reduceMotion: Bool, lowPower: Bool) -> Bool {
        visible && !reduceMotion && !lowPower
    }

    static func frame(at time: TimeInterval) -> [UInt8] {
        let phase = time.truncatingRemainder(dividingBy: loopDuration) / loopDuration
        var cells = [UInt8](repeating: 0, count: columns * rows)
        for column in 0..<columns {
            let x = Double(column) / Double(columns) + phase
            let far = ridge(0, at: x), middle = ridge(1, at: x), near = ridge(2, at: x)
            for row in 0..<rows {
                let y = Double(row) / Double(rows - 1)
                let depth: Int
                if y > near { depth = 2 }
                else if y > middle { depth = 1 }
                else if y > far { depth = 0 }
                else { continue }
                // Coherent tones change neighbouring letters gently; no random flicker.
                let tone = 0.5 + 0.28 * sin(x * 2 * .pi * 13 + y * 32)
                    + 0.18 * cos(x * 2 * .pi * 23 - y * 17)
                let level = min(4, max(0, Int(tone * 5)))
                if glyphs[depth][level] != " " {
                    cells[row * columns + column] = UInt8(1 + depth * 5 + level)
                }
            }
        }
        return cells
    }
}

/// A tiny reusable glyph atlas and a single frame buffer. Changed cells copy
/// cached pixels; font shaping is done once, never in the animation loop.
final class AmbientLandscapeRenderer {
    private static let stride = AmbientLandscape.width * 4
    private static let spriteStride = AmbientLandscape.cell * 4
    private var pixels = [UInt8](repeating: 0, count: AmbientLandscape.width * AmbientLandscape.height * 4)
    private var previous = [UInt8](repeating: 255, count: AmbientLandscape.columns * AmbientLandscape.rows)
    private(set) var changedCellCount = 0

    private static let sprites: [[UInt8]] = {
        let blank = [UInt8](repeating: 0, count: AmbientLandscape.cell * AmbientLandscape.line * 4)
        var result = [blank]
        let colors = [
            NSColor(calibratedRed: 0.34, green: 0.48, blue: 0.52, alpha: 0.44),
            NSColor(calibratedRed: 0.38, green: 0.47, blue: 0.36, alpha: 0.48),
            NSColor(calibratedRed: 0.54, green: 0.47, blue: 0.33, alpha: 0.48),
        ]
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        for depth in 0...2 {
            for glyph in AmbientLandscape.glyphs[depth] {
                guard let context = CGContext(data: nil, width: AmbientLandscape.cell, height: AmbientLandscape.line,
                                              bitsPerComponent: 8, bytesPerRow: spriteStride,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                      let data = context.data else { result.append(blank); continue }
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                (String(glyph) as NSString).draw(at: .zero, withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: colors[depth],
                ])
                result.append(Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: blank.count)))
            }
        }
        return result
    }()

    func render(at time: TimeInterval) -> CGImage? {
        let cells = AmbientLandscape.frame(at: time)
        changedCellCount = 0
        pixels.withUnsafeMutableBytes { destination in
            guard let base = destination.baseAddress else { return }
            for index in cells.indices where cells[index] != previous[index] {
                changedCellCount += 1
                let x = (index % AmbientLandscape.columns) * AmbientLandscape.cell
                let y = (index / AmbientLandscape.columns) * AmbientLandscape.line
                Self.sprites[Int(cells[index])].withUnsafeBytes { source in
                    guard let sprite = source.baseAddress else { return }
                    for line in 0..<AmbientLandscape.line {
                        memcpy(base.advanced(by: (y + line) * Self.stride + x * 4),
                               sprite.advanced(by: line * Self.spriteStride), Self.spriteStride)
                    }
                }
            }
        }
        previous = cells
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: AmbientLandscape.width, height: AmbientLandscape.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Self.stride,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

struct AmbientLandscapeView: NSViewRepresentable {
    var reduceMotion: Bool
    func makeNSView(context: Context) -> AmbientLandscapeNSView { AmbientLandscapeNSView(frame: .zero) }
    func updateNSView(_ view: AmbientLandscapeNSView, context: Context) {
        view.reduceMotion = reduceMotion
        view.updatePlayback()
    }
}

final class AmbientLandscapeNSView: NSView {
    var reduceMotion = false
    private let imageLayer = CALayer()
    private let renderer = AmbientLandscapeRenderer()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var sceneTime: TimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    var isPlaying: Bool { timer != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contents = renderer.render(at: 0)
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updatePlayback()
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        updatePlayback()
    }

    override func layout() {
        super.layout()
        let scale = max(bounds.width / AmbientLandscape.size.width, bounds.height / AmbientLandscape.size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = CGRect(x: (bounds.width - AmbientLandscape.size.width * scale) / 2, y: 0,
                                  width: AmbientLandscape.size.width * scale, height: AmbientLandscape.size.height * scale)
        CATransaction.commit()
        updatePlayback()
    }

    func updatePlayback() {
        let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
        let play = AmbientLandscape.shouldAnimate(visible: visible && !isHiddenOrHasHiddenAncestor,
                                                  reduceMotion: reduceMotion,
                                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        guard play != isPlaying else { return }
        if play {
            lastTick = CACurrentMediaTime()
            let timer = Timer(timeInterval: AmbientLandscape.frameInterval, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.025
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        updatePlayback()
        guard isPlaying else { return }
        let now = CACurrentMediaTime()
        sceneTime = (sceneTime + min(0.25, now - lastTick)).truncatingRemainder(dividingBy: AmbientLandscape.loopDuration)
        lastTick = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = renderer.render(at: sceneTime)
        CATransaction.commit()
    }
}
