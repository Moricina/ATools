import Foundation

public enum LauncherItemType: String, Codable {
    case application
    case fileOrFolder
    case webURL
    case shellScript
    case appleScript
    case systemAction
}

public enum TerminalMode: String, Codable {
    case integratedBackground
    case launchTerminal
    case openWith
}

public struct ExecutionContext: Codable {
    public var arguments: [String]
    public var workingDirectory: String?
    public var environmentVars: [String: String]
    public var runAsAdmin: Bool
    public var terminalMode: TerminalMode

    public init(
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environmentVars: [String: String] = [:],
        runAsAdmin: Bool = false,
        terminalMode: TerminalMode = .integratedBackground
    ) {
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentVars = environmentVars
        self.runAsAdmin = runAsAdmin
        self.terminalMode = terminalMode
    }
}

public struct LauncherItem: Identifiable, Codable {
    public var id: UUID
    public var parentId: UUID?
    public var name: String
    public var itemType: LauncherItemType
    public var target: String
    public var executionContext: ExecutionContext?
    public var customIconPath: String?
    public var hotkey: String?
    public var tags: [String]
    public var sortWeight: Int
    public var isVirtualGroup: Bool

    public init(
        id: UUID = UUID(),
        parentId: UUID? = nil,
        name: String,
        itemType: LauncherItemType,
        target: String,
        executionContext: ExecutionContext? = nil,
        customIconPath: String? = nil,
        hotkey: String? = nil,
        tags: [String] = [],
        sortWeight: Int = 0,
        isVirtualGroup: Bool = false
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.itemType = itemType
        self.target = target
        self.executionContext = executionContext
        self.customIconPath = customIconPath
        self.hotkey = hotkey
        self.tags = tags
        self.sortWeight = sortWeight
        self.isVirtualGroup = isVirtualGroup
    }
}

public struct Category: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var iconSymbol: String
    public var sortWeight: Int
    public var items: [LauncherItem]

    public init(
        id: UUID = UUID(),
        name: String,
        iconSymbol: String = "folder",
        sortWeight: Int = 0,
        items: [LauncherItem] = []
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.sortWeight = sortWeight
        self.items = items
    }
}
