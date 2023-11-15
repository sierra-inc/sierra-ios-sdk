// Copyright Sierra

import UIKit

class SendButton: UIButton {
    static let defaultSize = CGSize(width: 32, height: 32)

    init(fillColor: UIColor, strokeColor: UIColor, action: UIAction) {
        super.init(frame: .zero)
        addAction(action, for: .primaryActionTriggered)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(named: "SendArrow", in: .module, compatibleWith: nil)
        configuration.cornerStyle = .capsule
        // Override standard button disabled appearance (that tints to a grayscale
        // appearance that is not to our liking).
        configuration.imageColorTransformer = UIConfigurationColorTransformer { incoming in
            return strokeColor
        }
        configuration.background.backgroundColorTransformer = UIConfigurationColorTransformer { [weak self] incoming in
            guard let self else { return incoming }
            return self.state == .disabled ? .label.withAlphaComponent(0.3) : fillColor
        }
        self.configuration = configuration
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    override var intrinsicContentSize: CGSize {
        return SendButton.defaultSize
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.5 : 1.0
        }
    }
}
