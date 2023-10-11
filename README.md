# Sierra iOS SDK

## Installation

The SDK is available via Swift Package Manager. To add it as a dependency:

1. From the "File" menu, choose "Add Packages…"
2. Enter the URL for this repository (https://github.com/sierra-inc/sierra-ios-sdk) in the search box of at upper-right corner of the window.
3. Click "Add Package"

## Usage

The SDK is available as a high-level UI component or as as a low-level set of API classes. Both can be accessed via the `SierraSDK` module, and they share configuration information.

### Configuration

```swift
// Configure the agent. The agent token is provided by Sierra, and is specific
// to your account and the agent that you want to load.
let agentConfig = AgentConfig(token: "...")
let agent = loadAgent(config: agentConfig)
```

### UI API

A conversation UI can be shown by creating an `AgentChatController` and presenting it in your app.

```swift
let agentControllerOptions = AgentChatControllerOptions(name: "AI Assistant")
let agentController = AgentChatController(agent: agent, options: agentControllerOptions)

// Present the agent view controller in your app
```

#### Customization

`AgentChatControllerOptions` has several properties that can be used to customize the appearance and behavior of the conversation UI, please refer to its field comments for details.

Initial configuration (variables and secrets) can be provided via the `conversationOptions` property.

#### State Changes

To be notified of changes in the conversation, provide a `ConversationDelegate` in the controller options:

```swift
class MyConversationDelegate : ConversationDelegate {
    func conversation(_ conversation: Conversation, didTransfer transfer: ConversationTransfer) {
        // Handle a transfer to a customer service agent
    }
}

agentControllerOptions.conversationDelegate = MyConversationDelegate()
```

### Low-Level API

To be documented
