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
        editMenu.addItem(menuItem("撤销", action: Selector(("undo:")), key: "z"))
        editMenu.addItem(menuItem("重做", action: Selector(("redo:")), key: "Z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(menuItem("复制", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(menuItem("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != toggleStrikeSelector || focusedOutlineField() != nil
    }

    private func focusedOutlineField() -> NSTextField? {
        if let activeField = activeField,
           activeField.currentEditor() != nil,
           activeField.responds(to: toggleStrikeSelector) {
            return activeField
        }
        let application = NSApplication.shared
        let windows = ([application.keyWindow] + application.windows.map(Optional.some))
            .compactMap { $0 }
        for window in windows {
            guard let editor = window.firstResponder as? NSTextView,
                  let contentView = window.contentView else { continue }
            if let field = textFields(in: contentView).first(where: {
                $0.currentEditor() === editor && $0.responds(to: toggleStrikeSelector)
            }) {
                return field
            }
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
