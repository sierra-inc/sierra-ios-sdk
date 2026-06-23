// Copyright Sierra

import UIKit

public protocol VoiceMuteLevelDisplaying: AnyObject {
    func setInputLevel(_ level: Float)
    func setOutputLevel(_ level: Float)
    func resetLevels()
}

final class VoiceAudioLevelView: UIView {
    var inputColor: UIColor = UIColor(red: 0 / 255, green: 212 / 255, blue: 255 / 255, alpha: 1) {
        didSet { setNeedsDisplay() }
    }

    var outputColor: UIColor = UIColor(red: 180 / 255, green: 217 / 255, blue: 140 / 255, alpha: 1) {
        didSet { setNeedsDisplay() }
    }

    var micColor: UIColor = .white {
        didSet { setNeedsDisplay() }
    }

    var levelGain: Float = 6.0

    private let micImage: UIImage?
    private var targetInputLevel: Float = 0
    private var targetOutputLevel: Float = 0
    private var smoothedInputLevel: CGFloat = 0
    private var smoothedOutputLevel: CGFloat = 0
    private var displayLink: CADisplayLink?
    private let levelEpsilon: CGFloat = 0.001

    init(micImage: UIImage?) {
        self.micImage = micImage
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.svgWidth, height: Self.svgHeight)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else {
            updateDisplayLinkState()
        }
    }

    override var isHidden: Bool {
        didSet { updateDisplayLinkState() }
    }

    func setInputLevel(_ level: Float) {
        dispatchPrecondition(condition: .onQueue(.main))
        targetInputLevel = clampedLevel(level)
        updateDisplayLinkState()
    }

    func setOutputLevel(_ level: Float) {
        dispatchPrecondition(condition: .onQueue(.main))
        targetOutputLevel = clampedLevel(level)
        updateDisplayLinkState()
    }

    func resetLevels() {
        dispatchPrecondition(condition: .onQueue(.main))
        targetInputLevel = 0
        targetOutputLevel = 0
        smoothedInputLevel = 0
        smoothedOutputLevel = 0
        setNeedsDisplay()
        stopDisplayLink()
    }

    private func configure() {
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
        isUserInteractionEnabled = false
    }

    private func clampedLevel(_ raw: Float) -> Float {
        let scaled = raw * levelGain
        return min(1, max(0, scaled))
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateDisplayLinkState() {
        guard window != nil, !isHidden else {
            stopDisplayLink()
            return
        }
        if needsSmoothing {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    private static let attackCoef: CGFloat = 0.62
    private static let releaseCoef: CGFloat = 0.26

    @objc private func tick() {
        smoothedInputLevel = blend(current: smoothedInputLevel, target: CGFloat(targetInputLevel))
        smoothedOutputLevel = blend(current: smoothedOutputLevel, target: CGFloat(targetOutputLevel))
        snapSettledLevels()
        setNeedsDisplay()
        updateDisplayLinkState()
    }

    private func blend(current: CGFloat, target: CGFloat) -> CGFloat {
        let coef = target > current ? Self.attackCoef : Self.releaseCoef
        return current + (target - current) * coef
    }

    private var needsSmoothing: Bool {
        abs(smoothedInputLevel - CGFloat(targetInputLevel)) > levelEpsilon ||
            abs(smoothedOutputLevel - CGFloat(targetOutputLevel)) > levelEpsilon
    }

    private func snapSettledLevels() {
        if abs(smoothedInputLevel - CGFloat(targetInputLevel)) <= levelEpsilon {
            smoothedInputLevel = CGFloat(targetInputLevel)
        }
        if abs(smoothedOutputLevel - CGFloat(targetOutputLevel)) <= levelEpsilon {
            smoothedOutputLevel = CGFloat(targetOutputLevel)
        }
    }

    private static let svgWidth: CGFloat = 19
    private static let svgHeight: CGFloat = 29
    private static let innerCapsuleX: CGFloat = 6.63135
    private static let innerCapsuleY: CGFloat = 1.96436
    private static let innerCapsuleWidth: CGFloat = 5.60305
    private static let innerCapsuleHeight: CGFloat = 14.69974
    private static let ovalWidth: CGFloat = innerCapsuleWidth
    private static let ovalMaxHeight: CGFloat = innerCapsuleHeight

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = min(bounds.width / Self.svgWidth, bounds.height / Self.svgHeight)
        let drawW = Self.svgWidth * scale
        let drawH = Self.svgHeight * scale
        let offsetX = (bounds.width - drawW) / 2
        let offsetY = (bounds.height - drawH) / 2

        context.saveGState()
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)

        micImage?
            .withTintColor(micColor, renderingMode: .alwaysOriginal)
            .draw(in: CGRect(x: 0, y: 0, width: Self.svgWidth, height: Self.svgHeight))
        drawOvals(context: context)

        context.restoreGState()
    }

    private func drawOvals(context: CGContext) {
        let centerX = Self.innerCapsuleX + Self.innerCapsuleWidth / 2
        let baseY = Self.innerCapsuleY + Self.innerCapsuleHeight
        let inputHeight = Self.ovalMaxHeight * smoothedInputLevel
        let outputHeight = Self.ovalMaxHeight * smoothedOutputLevel

        let clipRect = CGRect(
            x: Self.innerCapsuleX,
            y: Self.innerCapsuleY,
            width: Self.innerCapsuleWidth,
            height: Self.innerCapsuleHeight
        )
        let clipPath = UIBezierPath(roundedRect: clipRect, cornerRadius: Self.innerCapsuleWidth / 2).cgPath

        context.saveGState()
        context.addPath(clipPath)
        context.clip()

        if outputHeight > 0 {
            let outputRect = CGRect(x: centerX - Self.ovalWidth / 2, y: baseY - outputHeight, width: Self.ovalWidth, height: outputHeight)
            context.setBlendMode(.normal)
            context.setFillColor(outputColor.cgColor)
            context.addPath(UIBezierPath(roundedRect: outputRect, cornerRadius: Self.ovalWidth / 2).cgPath)
            context.fillPath()
        }

        if inputHeight > 0 {
            let inputRect = CGRect(x: centerX - Self.ovalWidth / 2, y: baseY - inputHeight, width: Self.ovalWidth, height: inputHeight)
            context.setBlendMode(.hardLight)
            context.setFillColor(inputColor.cgColor)
            context.addPath(UIBezierPath(roundedRect: inputRect, cornerRadius: Self.ovalWidth / 2).cgPath)
            context.fillPath()
        }

        context.setBlendMode(.normal)
        context.restoreGState()
    }
}
