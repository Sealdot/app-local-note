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
