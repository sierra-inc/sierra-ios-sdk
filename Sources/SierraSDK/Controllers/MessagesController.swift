// Copyright Sierra

import UIKit

class MessagesController : UITableViewController, ConversationDelegate {
    private let conversation: Conversation
    private let options: MessagesControllerOptions
    private var conversationError: Error?
    private var conversationErrorMessage: String?
    private var conversationHumanAgentParticipation: HumanAgentParticipation?
    // Errors are at the bottom, but are listed first due to the bottom-anchored transform
    private static let sections: [Section] = [.error, .humanAgentParticipation, .messages]

    init(conversation: Conversation, options: MessagesControllerOptions) {
        self.conversation = conversation
        self.options = options
        super.init(style: .plain)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    private lazy var dataSource = {
        let conversation = self.conversation
        let options = self.options
        return UITableViewDiffableDataSource<Section, MessageID>(
            tableView: tableView,
            cellProvider: { (tableView, indexPath, messageID) -> UITableViewCell? in
                let section = MessagesController.sections[indexPath.section]
                if section == Section.messages {
                    let message = conversation.messageWithID(messageID)
                    let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseIdentifier, for: indexPath) as! MessageCell
                    cell.applyChatStyle(options.chatStyle)
                    cell.message = message
                    var senderName: String? = nil
                    if let message, message.role == .humanAgent && conversation.shouldShowSenderName(messageID) {
                        senderName = self.conversationHumanAgentParticipation?.agent?.displayName
                    }
                    cell.senderName = senderName
                    return cell
                }
                if section == Section.error {
                    let cell = tableView.dequeueReusableCell(withIdentifier: ErrorCell.reuseIdentifier, for: indexPath) as! ErrorCell
                    cell.applyChatStyle(options.chatStyle)
                    cell.message = self.conversationErrorMessage ?? self.options.errorMessage
                    return cell
                }
                if section == Section.humanAgentParticipation {
                    let cell = tableView.dequeueReusableCell(withIdentifier: HumanAgentWaitingCell.reuseIdentifier, for: indexPath) as! HumanAgentWaitingCell
                    cell.applyOptions(options)
                    cell.participation = self.conversationHumanAgentParticipation
                    return cell
                }
                return nil
            })
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseIdentifier)
        tableView.register(ErrorCell.self, forCellReuseIdentifier: ErrorCell.reuseIdentifier)
        tableView.register(HumanAgentWaitingCell.self, forCellReuseIdentifier: HumanAgentWaitingCell.reuseIdentifier)
        tableView.dataSource = dataSource
        // Flip vertically to bottom anchor the scroll view. Cells also apply the same transform
        // so that content is not flipped.
        tableView.transform = FLIP_TRANSFORM
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.allowsSelection = false
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.backgroundColor = options.chatStyle.colors.backgroundColor

        if let disclosure = options.disclosure, !disclosure.isEmpty {
            // The disclosure is logically a header, but because of the flipped layout it needs
            // to be set as a footer to apepar at the top.
            tableView.tableFooterView = DisclosureFooterView(disclosure: disclosure, style:options.chatStyle)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, MessageID>()
        snapshot.appendSections(MessagesController.sections)
        // Items need to be reversed so that they end up in the right order after the
        // vertical flip transform.
        snapshot.appendItems(conversation.messages.reversed().map { $0.id }, toSection: .messages)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        conversation.addDelegate(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        conversation.removeDelegate(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let footerView = tableView.tableFooterView {
            let footerHeight = ceil(footerView.intrinsicContentSize.height)
            if footerView.frame.height != footerHeight {
                footerView.frame.size.height = footerHeight
                tableView.tableFooterView = footerView
            }
        }
    }

    // MARK: ConversationDelegate

    func conversation(_ conversation: Conversation, didAddMessages messageIDs: [MessageID]) {
        var snapshot = dataSource.snapshot()
        let existingMessageIDs = snapshot.itemIdentifiers(inSection: .messages)
        if existingMessageIDs.isEmpty {
            snapshot.appendItems(messageIDs.reversed(), toSection: .messages)
        } else {
            snapshot.insertItems(messageIDs.reversed(), beforeItem: existingMessageIDs[0])
        }
        self.conversationError = nil
        self.conversationErrorMessage = nil
        if snapshot.numberOfItems(inSection: .error) > 0 {
            snapshot.deleteItems([ErrorCell.id])
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    func conversation(_ conversation: Conversation, didRemoveMessage messageID: MessageID) {
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([messageID])
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    func conversation(_ conversation: Conversation, didChangeMessage messageID: MessageID) {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([messageID])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func conversation(_ conversation: Conversation, didHaveError error: Error?, withMessage message: String?) {
        self.conversationError = error
        self.conversationErrorMessage = message
        var snapshot = dataSource.snapshot()
        if snapshot.numberOfItems(inSection: .error) == 0 {
            snapshot.appendItems([ErrorCell.id], toSection: .error)
        } else {
            snapshot.reconfigureItems([ErrorCell.id])
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    func conversation(_ conversation: Conversation, didChangeHumanAgentParticipation participation: HumanAgentParticipation?, previousValue: HumanAgentParticipation?) {
        self.conversationHumanAgentParticipation = participation

        var snapshot = dataSource.snapshot()
        if participation?.state == .waiting {
            if snapshot.numberOfItems(inSection: .humanAgentParticipation) == 0 {
                snapshot.appendItems([HumanAgentWaitingCell.id], toSection: .humanAgentParticipation)
            } else {
                snapshot.reconfigureItems([HumanAgentWaitingCell.id])
            }
        } else {
            if snapshot.numberOfItems(inSection: .humanAgentParticipation) > 0 {
                snapshot.deleteItems([HumanAgentWaitingCell.id])
            }
        }
        dataSource.apply(snapshot, animatingDifferences: true)

        if participation?.state == .joined && (previousValue?.state == .waiting || previousValue?.state == .left) {
            conversation.addStatusMessage(options.humanAgentTransferJoinedMessage)
        } else if participation?.state == .left && previousValue?.state == .joined {
            conversation.addStatusMessage(options.humanAgentTransferLeftMessage)
        }
    }
}

struct MessagesControllerOptions {
    let disclosure: String?
    let humanAgentTransferWaitingMessage: String
    let humanAgentTransferQueueSizeMessage: String
    let humanAgentTransferQueueNextMessage: String
    let humanAgentTransferJoinedMessage: String
    let humanAgentTransferLeftMessage: String
    let errorMessage: String
    let chatStyle: ChatStyle
}

private enum Section: Int {
    case messages
    case humanAgentParticipation
    case error
}

private class DisclosureFooterView: UIView {
    private let labelView: UILabel
    private let xPadding: CGFloat

    init(disclosure: String, style: ChatStyle) {
        labelView = UILabel()
        xPadding = max(style.layout.bubbleXMargin + style.layout.bubbleXPadding, 40)
        super.init(frame: .zero)

        self.transform = FLIP_TRANSFORM
        labelView.text = disclosure
        labelView.numberOfLines = 0
        labelView.font = .preferredFont(forTextStyle: .caption1)
        labelView.textColor = style.colors.disclosureText
        labelView.adjustsFontForContentSizeCategory = false
        labelView.textAlignment = .center
        addSubview(labelView)

        labelView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: xPadding),
            labelView.topAnchor.constraint(equalTo: self.topAnchor),
            labelView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])

        // Slightly reduce the priority of the trailing contraint, otherwise it's unsatisfiable when the
        // footer view is first added to the table (and ends up with a width of 0).
        let trailingConstraint = labelView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -xPadding)
        trailingConstraint.priority = .defaultHigh
        trailingConstraint.isActive = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    override var intrinsicContentSize: CGSize {
        let width = self.frame.width
        let height = labelView.sizeThatFits(CGSize(width: width - 2*xPadding, height: CGFloat.greatestFiniteMagnitude)).height + 22
        return CGSize(width: width, height: height)
    }
}

private class MessageCell: UITableViewCell {
    fileprivate static let reuseIdentifier = String(describing: MessageCell.self)

    var message: Message? {
        didSet {
            if let message {
                render(message)
            }
        }
    }

    var senderName: String? {
        didSet {
            updateSenderName()
        }
    }

    var appliedChatStyle = false
    private var colors: ChatStyleColors?
    private var userConstraints: [NSLayoutConstraint] = []
    private var assistantConstraints: [NSLayoutConstraint] = []
    private var statusConstraints: [NSLayoutConstraint] = []
    private var senderNameShownConstraints: [NSLayoutConstraint] = []
    private var senderNameHiddenConstraints: [NSLayoutConstraint] = []

    private let textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.layer.masksToBounds = true
        return textView
    }()

    private let tailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "BubbleTail", in: .module, compatibleWith: nil)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintAdjustmentMode = .normal
        return imageView
    }()

    private let typingingIndicatorView: TypingIndicatorView = {
        let view = TypingIndicatorView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let senderNameLabel : UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        contentView.transform = FLIP_TRANSFORM
        contentView.addSubview(textView)
        contentView.addSubview(tailImageView)
        contentView.addSubview(typingingIndicatorView)
        contentView.addSubview(senderNameLabel)
        typingingIndicatorView.isHidden = true
    }

    fileprivate func applyChatStyle(_ chatStyle: ChatStyle) {
        if appliedChatStyle {
            return
        }

        let layout = chatStyle.layout
        textView.textContainerInset = UIEdgeInsets(
            top: layout.bubbleYPadding,
            left: layout.bubbleXPadding,
            bottom: layout.bubbleYPadding,
            right: layout.bubbleXPadding
        )
        textView.layer.cornerRadius = layout.bubbleRadius
        tailImageView.isHidden = !layout.bubbleTail

        var widthConstraints: [NSLayoutConstraint] = []
        if layout.bubbleMaxWidthFraction > 0 {
            widthConstraints.append(textView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: layout.bubbleMaxWidthFraction))
        }
        if layout.bubbleMaxWidthAbsolute > 0 {
            widthConstraints.append(textView.widthAnchor.constraint(lessThanOrEqualToConstant: layout.bubbleMaxWidthAbsolute))
        }

        let leadingAnchor = readableContentGuide.leadingAnchor
        let trailingAnchor = readableContentGuide.trailingAnchor

        userConstraints = [
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -layout.bubbleXMargin),
            textView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: layout.bubbleXMargin),
            tailImageView.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 5),
            senderNameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -layout.bubbleXMargin - layout.bubbleXPadding),
        ] + widthConstraints

        assistantConstraints = [
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.bubbleXMargin),
            textView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -layout.bubbleXMargin),
            tailImageView.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: -5),
            senderNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.bubbleXMargin + layout.bubbleXPadding),
        ] + widthConstraints

        statusConstraints = [
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.bubbleXMargin),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -layout.bubbleXMargin),
        ]

        senderNameShownConstraints = [
            textView.topAnchor.constraint(equalTo: senderNameLabel.bottomAnchor, constant: layout.bubbleYMargin),
            senderNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
        ]

        senderNameHiddenConstraints = [
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: layout.bubbleYMargin),
        ]

        NSLayoutConstraint.activate([
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -layout.bubbleYMargin),
            tailImageView.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: 1),

            // Make the typing indicator view track the size of the text view so that it also respects dyanmic text size.
            typingingIndicatorView.topAnchor.constraint(equalTo: textView.topAnchor, constant: layout.bubbleYPadding),
            typingingIndicatorView.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -layout.bubbleYPadding),
            typingingIndicatorView.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: layout.bubbleXPadding),
            typingingIndicatorView.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -layout.bubbleXPadding),
        ])

        appliedChatStyle = true
        colors = chatStyle.colors
        backgroundColor = chatStyle.colors.backgroundColor

        senderNameLabel.textColor = colors?.statusText
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    private func render(_ message: Message) {
        switch message.role {
        case .assistant, .humanAgent:
            textView.backgroundColor = colors?.assistantBubble
            textView.textColor = colors?.assistantBubbleText
            textView.font = UIFont.preferredFont(forTextStyle: .body)
            textView.textAlignment = .natural
            tailImageView.layer.opacity = 1.0
            tailImageView.tintColor = colors?.assistantBubble
            tailImageView.transform = CGAffineTransform.identity
            NSLayoutConstraint.deactivate(userConstraints)
            NSLayoutConstraint.activate(assistantConstraints)
            NSLayoutConstraint.deactivate(statusConstraints)
        case .user:
            textView.backgroundColor = colors?.userBubble
            textView.textColor = colors?.userBubbleText
            textView.font = UIFont.preferredFont(forTextStyle: .body)
            textView.textAlignment = .natural
            tailImageView.layer.opacity = 1.0
            tailImageView.tintColor = colors?.userBubble
            tailImageView.transform = CGAffineTransform(scaleX: -1, y: 1)
            NSLayoutConstraint.deactivate(assistantConstraints)
            NSLayoutConstraint.activate(userConstraints)
            NSLayoutConstraint.deactivate(statusConstraints)
        case .status:
            textView.backgroundColor = colors?.backgroundColor
            textView.textColor = colors?.statusText
            textView.font = .preferredFont(forTextStyle: .caption1)
            textView.textAlignment = .center
            tailImageView.layer.opacity = 0
            NSLayoutConstraint.deactivate(userConstraints)
            NSLayoutConstraint.deactivate(assistantConstraints)
            NSLayoutConstraint.activate(statusConstraints)
        }

        typingingIndicatorView.isHidden = true
        if message.role == .assistant || message.role == .humanAgent {
            if message.isTypingIndicator {
                typingingIndicatorView.isHidden = false
                if let dotColor = textView.textColor {
                    typingingIndicatorView.dotColor = dotColor
                }
                textView.text = message.content
                textView.textColor = .clear
                return
            }

            if let attributedContent = message.attributedContent(font: UIFont.preferredFont(forTextStyle: .body), textColor: textView.textColor) {
                textView.attributedText = NSMutableAttributedString(attributedContent)
                return
            }
        }
        textView.text = message.content
    }

    private func updateSenderName() {
        if let senderName {
            senderNameLabel.text = senderName
            senderNameLabel.isHidden = false
            NSLayoutConstraint.deactivate(senderNameHiddenConstraints)
            NSLayoutConstraint.activate(senderNameShownConstraints)
        } else {
            senderNameLabel.isHidden = true
            NSLayoutConstraint.activate(senderNameHiddenConstraints)
            NSLayoutConstraint.deactivate(senderNameShownConstraints)
        }
    }
}

private class ErrorCell: UITableViewCell {
    fileprivate static let id: MessageID = UUID()
    fileprivate static let reuseIdentifier = String(describing: ErrorCell.self)

    var message: String? {
        didSet {
            if let message {
                render(message)
            }
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        contentView.transform = FLIP_TRANSFORM
        textLabel?.numberOfLines = 0
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    fileprivate func applyChatStyle(_ chatStyle: ChatStyle) {
        textLabel?.textColor = chatStyle.colors.errorText
        backgroundColor = chatStyle.colors.backgroundColor
    }

    private func render(_ message: String) {
        textLabel?.text = message
    }
}

private class HumanAgentWaitingCell: UITableViewCell {
    fileprivate static let id: MessageID = UUID()
    fileprivate static let reuseIdentifier = String(describing: ErrorCell.self)

    var participation: HumanAgentParticipation? {
        didSet {
            if let participation {
                render(participation)
            }
        }
    }

    private var options: MessagesControllerOptions?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        contentView.transform = FLIP_TRANSFORM
        textLabel?.numberOfLines = 0
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    fileprivate func applyOptions(_ options: MessagesControllerOptions) {
        let colors = options.chatStyle.colors
        textLabel?.textColor = colors.statusText
        textLabel?.textAlignment = .center
        textLabel?.font = .preferredFont(forTextStyle: .caption1)
        backgroundColor = colors.backgroundColor
        self.options = options
    }

    private func render(_ participation: HumanAgentParticipation) {
        guard let options else { return }
        guard let textLabel else { return }

        if let queueSize = participation.queueSize {
            if queueSize == 0 {
                textLabel.text = options.humanAgentTransferQueueNextMessage
            } else {
                let ordinalFormatter = NumberFormatter()
                ordinalFormatter.numberStyle = .ordinal
                if let position = ordinalFormatter.string(from: NSNumber(value: queueSize)) {
                    textLabel.text = options.humanAgentTransferQueueSizeMessage.replacingOccurrences(of: "{POSITION}", with: position)
                } else {
                    textLabel.text = options.humanAgentTransferWaitingMessage
                }
            }
        } else {
            textLabel.text = options.humanAgentTransferWaitingMessage
        }
    }
}


fileprivate let FLIP_TRANSFORM = CGAffineTransform(scaleX: 1, y: -1)
