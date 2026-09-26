import AppKit

enum ApplicationMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu(title: "Local Note")

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Local Note")
        applicationMenu.addItem(
            withTitle: "退出 Local Note",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        let undoItem = menuItem(
            "撤销",
            action: #selector(OutlineCommandRouter.undoLocalNote(_:)),
            key: "z"
        )
        undoItem.target = OutlineCommandRouter.shared
        editMenu.addItem(undoItem)
        let redoItem = menuItem(
            "重做",
            action: #selector(OutlineCommandRouter.redoLocalNote(_:)),
            key: "Z",
            modifiers: [.command, .shift]
        )
        redoItem.target = OutlineCommandRouter.shared
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        let copyItem = menuItem(
            "复制",
            action: #selector(OutlineCommandRouter.copyLocalNote(_:)),
            key: "c"
        )
        copyItem.target = OutlineCommandRouter.shared
        editMenu.addItem(copyItem)
        let pasteItem = menuItem(
            "粘贴",
            action: #selector(OutlineCommandRouter.pasteLocalNote(_:)),
            key: "v"
        )
        pasteItem.target = OutlineCommandRouter.shared
        editMenu.addItem(pasteItem)
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        editMenu.addItem(.separator())
        let strikeItem = menuItem(
            "切换划线",
            action: #selector(OutlineCommandRouter.toggleLocalNoteStrikethrough(_:)),
            key: "s",
            modifiers: [.command, .shift]
        )
        strikeItem.target = OutlineCommandRouter.shared
        editMenu.addItem(strikeItem)
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }

    private static func menuItem(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

final class OutlineCommandRouter: NSObject, NSMenuItemValidation {
    static let shared = OutlineCommandRouter()

    private let toggleStrikeSelector = #selector(OutlineCommandRouter.toggleLocalNoteStrikethrough(_:))
    private let copySelector = #selector(OutlineCommandRouter.copyLocalNote(_:))
    private let pasteSelector = #selector(OutlineCommandRouter.pasteLocalNote(_:))
    private let undoSelector = #selector(OutlineCommandRouter.undoLocalNote(_:))
    private let redoSelector = #selector(OutlineCommandRouter.redoLocalNote(_:))
    private weak var activeField: NSTextField?

    func didBeginEditing(_ field: NSTextField) {
        activeField = field
    }

    func didEndEditing(_ field: NSTextField) {
        if activeField === field { activeField = nil }
    }

    @objc func toggleLocalNoteStrikethrough(_ sender: Any?) {
        guard let field = focusedOutlineField() else { return }
        _ = NSApplication.shared.sendAction(toggleStrikeSelector, to: field, from: sender)
    }

    @objc func copyLocalNote(_ sender: Any?) {
        if let field = focusedOutlineField() {
            _ = NSApplication.shared.sendAction(copySelector, to: field, from: sender)
            return
        }
        _ = NSApplication.shared.sendAction(#selector(NSText.copy(_:)), to: nil, from: sender)
    }

    @objc func pasteLocalNote(_ sender: Any?) {
        if let field = focusedOutlineField() {
            field.perform(pasteSelector, with: sender)
            return
        }
        let application = NSApplication.shared
        let responder = application.orderedWindows
            .first(where: { $0.isVisible && $0.firstResponder is NSTextView })?
            .firstResponder
            ?? application.keyWindow?.firstResponder
        _ = application.sendAction(
            #selector(NSText.paste(_:)),
            to: responder,
            from: sender
        )
    }

    @objc func undoLocalNote(_ sender: Any?) {
        guard let field = focusedOutlineField() else { return }
        _ = NSApplication.shared.sendAction(undoSelector, to: field, from: sender)
    }

    @objc func redoLocalNote(_ sender: Any?) {
        guard let field = focusedOutlineField() else { return }
        _ = NSApplication.shared.sendAction(redoSelector, to: field, from: sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case toggleStrikeSelector,
             #selector(OutlineCommandRouter.undoLocalNote(_:)),
             #selector(OutlineCommandRouter.redoLocalNote(_:)):
            return focusedOutlineField() != nil
        default:
            return true
        }
    }

    private func focusedOutlineField() -> NSTextField? {
        let application = NSApplication.shared
        let windows = (application.orderedWindows
            .filter(\.isVisible)
            .map(Optional.some)).compactMap { $0 }
        for window in windows {
            guard let editor = window.firstResponder as? NSTextView,
                  let contentView = window.contentView else { continue }
            if let field = textFields(in: contentView).first(where: {
                $0.currentEditor() === editor && $0.responds(to: toggleStrikeSelector)
            }) {
                return field
            }
        }
        if let activeField = activeField,
           activeField.window?.isKeyWindow == true,
           activeField.currentEditor() != nil,
           activeField.responds(to: toggleStrikeSelector) {
            return activeField
        }
        return nil
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var fields = view.subviews.compactMap { $0 as? NSTextField }
        for subview in view.subviews {
            fields.append(contentsOf: textFields(in: subview))
        }
        return fields
    }
}
