// Copyright Sierra

import UIKit

class MessagesController : UITableViewController, ConversationDelegate {
    private let conversation: Conversation
    private let options: MessagesControllerOptions
    private var conversationError: Error?
    private var conversationErrorMessage: String?
    // Errors are at the bottom, but are listed first due to the bottom-anchored transform
    private static let sections: [Section] = [.error, .messages]

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
        let chatStyle = self.options.chatStyle
        return UITableViewDiffableDataSource<Section, MessageID>(
            tableView: tableView,
            cellProvider: { (tableView, indexPath, messageID) -> UITableViewCell? in
                if MessagesController.sections[indexPath.section] == Section.messages {
                    let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseIdentifier, for: indexPath) as! MessageCell
                    cell.applyChatStyle(chatStyle)
                    cell.message = conversation.messageWithID(messageID)
                    return cell
                }
                if MessagesController.sections[indexPath.section] == Section.error {
                    let cell = tableView.dequeueReusableCell(withIdentifier: ErrorCell.reuseIdentifier, for: indexPath) as! ErrorCell
                    cell.message = self.conversationErrorMessage ?? self.options.errorMessage
                    return cell
                }
                return nil
            })
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseIdentifier)
        tableView.register(ErrorCell.self, forCellReuseIdentifier: ErrorCell.reuseIdentifier)
        tableView.dataSource = dataSource
        // Flip vertically to bottom anchor the scroll view. Cells also apply the same transform
        // so that content is not flipped.
        self.tableView.transform = FLIP_TRANSFORM
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.allowsSelection = false
        tableView.cellLayoutMarginsFollowReadableWidth = true

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
}

struct MessagesControllerOptions {
    let disclosure: String?
    let errorMessage: String
    let chatStyle: ChatStyle
}

private enum Section: Int {
    case messages
    case error
}

private class DisclosureFooterView: UIView {
    private let labelView: UILabel
    private let xPadding: CGFloat

    init(disclosure: String, style: ChatStyle) {
        labelView = UILabel()
        xPadding = style.layout.bubbleXMargin + style.layout.bubbleXPadding
        super.init(frame: .zero)

        self.transform = FLIP_TRANSFORM
        labelView.text = disclosure
        labelView.numberOfLines = 0
        labelView.font = .preferredFont(forTextStyle: .caption1)
        labelView.textColor = style.colors.disclosureText
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
        let height = labelView.sizeThatFits(CGSize(width: width - 2*xPadding, height: CGFloat.greatestFiniteMagnitude)).height
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

    var appliedChatStyle = false
    private var colors: ChatStyleColors?
    private var userConstraints: [NSLayoutConstraint] = []
    private var assistantConstraints: [NSLayoutConstraint] = []

    private let textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.textContainer.lineFragmentPadding = 0
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.layer.cornerRadius = 16
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

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        contentView.transform = FLIP_TRANSFORM
        contentView.addSubview(textView)
        contentView.addSubview(tailImageView)
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

        if layout.bubbleMaxWidthFraction > 0 {
            textView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: layout.bubbleMaxWidthFraction).isActive = true
        }
        if layout.bubbleMaxWidthAbsolute > 0 {
            textView.widthAnchor.constraint(lessThanOrEqualToConstant: layout.bubbleMaxWidthAbsolute).isActive = true
        }

        let leadingAnchor = readableContentGuide.leadingAnchor
        let trailingAnchor = readableContentGuide.trailingAnchor

        userConstraints = [
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -layout.bubbleXMargin),
            textView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: layout.bubbleXMargin),
            tailImageView.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -17.5),
        ]

        assistantConstraints = [
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.bubbleXMargin),
            textView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -layout.bubbleXMargin),
            tailImageView.trailingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 17.5),
        ]

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: layout.bubbleYMargin),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -layout.bubbleYMargin),
            tailImageView.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: 4),
        ])

        appliedChatStyle = true
        colors = chatStyle.colors
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    private func render(_ message: Message) {
        switch message.role {
        case .assistant:
            textView.backgroundColor = colors?.assistantBubble
            textView.textColor = colors?.assistantBubbleText
            tailImageView.tintColor = colors?.assistantBubble
            tailImageView.transform = CGAffineTransform.identity
            NSLayoutConstraint.deactivate(userConstraints)
            NSLayoutConstraint.activate(assistantConstraints)
        case .user:
            textView.backgroundColor = colors?.userBubble
            textView.textColor = colors?.userBubbleText
            tailImageView.tintColor = colors?.userBubble
            tailImageView.transform = CGAffineTransform(scaleX: -1, y: 1)
            NSLayoutConstraint.deactivate(assistantConstraints)
            NSLayoutConstraint.activate(userConstraints)
        }

        if message.role == .assistant {
            if let attributedContent = message.attributedContent(font: UIFont.preferredFont(forTextStyle: .body), textColor: textView.textColor) {
                textView.attributedText = NSMutableAttributedString(attributedContent)
                return
            }
        }
        textView.text = message.content
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
        textLabel?.textColor = .systemRed
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    private func render(_ message: String) {
        textLabel?.text = message
    }
}

fileprivate let FLIP_TRANSFORM = CGAffineTransform(scaleX: 1, y: -1)
