// Copyright Sierra

import UIKit

public final class EndCallButtonLegacy: UIButton {
    private let buttonSize: CGFloat = 56

    public init(
        backgroundColor: UIColor,
        iconColor: UIColor,
        icon: UIImage?
    ) {
        super.init(frame: .zero)
        configure(backgroundColor: backgroundColor, iconColor: iconColor, icon: icon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(backgroundColor: UIColor, iconColor: UIColor, icon: UIImage?) {
        translatesAutoresizingMaskIntoConstraints = false
        setImage((icon ?? UIImage(systemName: "phone.down.fill"))?.withRenderingMode(.alwaysTemplate), for: .normal)
        tintColor = iconColor
        self.backgroundColor = backgroundColor
        layer.cornerRadius = buttonSize / 2
        clipsToBounds = true
        accessibilityLabel = "End call"
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: buttonSize),
            heightAnchor.constraint(equalToConstant: buttonSize),
        ])
    }
}
