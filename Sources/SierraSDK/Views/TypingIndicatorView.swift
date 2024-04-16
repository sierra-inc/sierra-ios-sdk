// Copyright Sierra

import UIKit

class TypingIndicatorView: UIView {
    var dotColor: UIColor {
        didSet {
            updateDotColors()
        }
    }
    private let dotLayers = [CALayer(), CALayer(), CALayer()]

    override init(frame: CGRect) {
        self.dotColor = .darkGray
        super.init(frame: frame)
        dotLayers.forEach { layer.addSublayer($0) }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let dotDiameter = self.frame.width / 5
        let dotRadius = dotDiameter / 2
        let centerY = self.frame.height / 2

        for (index, dotLayer) in dotLayers.enumerated() {
            let xOffset = dotDiameter * CGFloat(index * 2)
            dotLayer.cornerRadius = dotRadius
            dotLayer.frame = CGRect(x: xOffset, y: centerY - dotRadius, width: dotDiameter, height: dotDiameter)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
       super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateDotColors()
        }
    }

    private func startAnimating() {
        var delay = 0.0
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.2
        animation.duration = 0.6
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = Float.infinity

        for dotLayer in dotLayers {
            dotLayer.add(animation, forKey: "opacityPulse")
            animation.beginTime = CACurrentMediaTime() + delay
            delay += 0.2
        }
    }

    private func stopAnimating() {
        for dotLayer in dotLayers {
            dotLayer.removeAnimation(forKey: "opacityPulse")
        }
    }

    private func updateDotColors() {
        dotLayers.forEach { $0.backgroundColor = dotColor.cgColor }
    }
}
