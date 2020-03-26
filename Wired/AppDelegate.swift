//
//  AppDelegate.swift
//  Wired 3
//
//  Created by Rafael Warnault on 15/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa
import Wired
import Preferences
import KeychainAccess
import UserNotifications

extension PreferencePane.Identifier {
    static let general      = Identifier("general")
    static let chat         = Identifier("chat")
    static let files        = Identifier("files")
    static let advanced     = Identifier("advanced")
}

extension Notification.Name {
    static let didAddNewBookmark = Notification.Name("didAddNewBookmark")
}

extension UserDefaults {
    func image(forKey key: String) -> NSImage? {
        var image: NSImage?
        if let imageData = data(forKey: key) {
            image = try! NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: imageData)
        }
        return image
    }
    func set(image: NSImage?, forKey key: String) {
        var imageData: NSData?
        if let image = image {
            imageData = try! NSKeyedArchiver.archivedData(withRootObject: image, requiringSecureCoding: false) as NSData
        }
        set(imageData, forKey: key)
    }
}

public let spec = P7Spec()

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    public static let shared:AppDelegate = NSApp.delegate as! AppDelegate
    
    public static var unreadChatMessages = 0
    public static var unreadPrivateMessages = 0
    
    static let notificationCenter = UNUserNotificationCenter.current()
    static let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    
    static let dateTimeFormatter = DateFormatter()
    static let byteCountFormatter = ByteCountFormatter()
    
    
    lazy var preferencesWindowController = PreferencesWindowController(
        preferencePanes: [
            GeneralPreferenceViewController(),
            ChatPreferenceViewController(),
            FilesPreferenceViewController(),
            AdvancedPreferenceViewController()
        ]
    )
    
    public static var currentIcon:NSImage? {
        get {
            return UserDefaults.standard.image(forKey: "WSUserIcon")
        }
    }
    
    private static var defaultUserIconData:Data? {
        get {
            return Data(base64Encoded: Wired.defaultUserIcon, options: .ignoreUnknownCharacters)
        }
    }
    
    private static var defaultIcon:NSImage? {
        get {
            if let imageData = defaultUserIconData {
                return NSImage(data: imageData)
            }
            
            return nil
        }
    }
    
    
    override init() {
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        
        // Default preferences
        UserDefaults.standard.register(defaults: [
            "WSUserNick": "WiredSwift",
            "WSUserStatus": "Share The Wealth",
            "WSCheckActiveConnectionsBeforeQuit": true,
            "WSDownloadDirectory": downloadsDirectory,
            "WSEmojiSubstitutionsEnabled": true,
            "WSEmojiSubstitutions": [
                ":-)": "😊",
                ":)":  "😊",
                ";-)": "😉",
                ";)":  "😉",
                ":-D": "😀",
                ":D":  "😀",
                "<3":  "❤️",
                "+1":  "👍"
            ]
        ])
        
        UserDefaults.standard.synchronize()
        
        // default icon
        if UserDefaults.standard.image(forKey: "WSUserIcon") == nil {
            UserDefaults.standard.set(image: AppDelegate.defaultIcon, forKey: "WSUserIcon")
        }
    
        AppDelegate.byteCountFormatter.allowedUnits = [.useMB]
        AppDelegate.byteCountFormatter.countStyle = .file
        AppDelegate.byteCountFormatter.zeroPadsFractionDigits = true
        
        AppDelegate.dateTimeFormatter.dateStyle = .medium
        AppDelegate.dateTimeFormatter.timeStyle = .medium
    }
    
    // MARK: - Application Delegate
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // request notifications
        AppDelegate.notificationCenter.requestAuthorization(options: AppDelegate.options) {
            (didAllow, error) in
            if !didAllow {
                print("User has declined notifications")
            }
        }
        AppDelegate.notificationCenter.delegate = self
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if UserDefaults.standard.bool(forKey: "WSCheckActiveConnectionsBeforeQuit") == true {
            if AppDelegate.hasActiveConnections() {
                let alert = NSAlert()
                alert.messageText = "Are you sure you want to quit?"
                alert.informativeText = "Every connections will be disconnected"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
                                
                if alert.runModal() == .alertFirstButtonReturn {
                    return self.safeTerminateApp(sender)
                } else {
                    return NSApplication.TerminateReply.terminateCancel
                }
            }
        }
        
        return self.safeTerminateApp(sender)
    }
    
    
    private func safeTerminateApp(_ sender: NSApplication) -> NSApplication.TerminateReply  {
        for c in ConnectionsController.shared.connections {
            if let cwc = c.connectionWindowController {
                if cwc.connection != nil {
                    cwc.connection.disconnect()
                }
            }
        }
        
        return self.terminateCoreData(sender)
    }
    
    
    func applicationWillTerminate(_ aNotification: Notification) {

    }
    
    
    
    
    // MARK: - IB Actions
    @IBAction func connect(_ sender: Any) {

    }
    
    
    @IBAction func showChat(_ sender: Any) {
        self.setTabView(atIndex: 0)
        
        NSApp.mainWindow?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Chat")
    }
    
    @IBAction func showMessages(_ sender: Any) {
        self.setTabView(atIndex: 1)
        NSApp.mainWindow?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Messages")
    }
    
    @IBAction func showBoards(_ sender: Any) {
        self.setTabView(atIndex: 2)
        NSApp.mainWindow?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Boards")
    }
    
    @IBAction func showFiles(_ sender: Any) {
        self.setTabView(atIndex: 3)
        NSApp.mainWindow?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Files")
    }
    
    @IBAction func showTransfers(_ sender: Any) {
        self.setTabView(atIndex: 4)
        NSApp.mainWindow?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Transfers")
    }
    
    @IBAction func showInfos(_ sender: Any) {
        self.setTabView(atIndex: 5)
        NSApp.mainWindow?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Infos")
    }
    
    @IBAction func showSettings(_ sender: Any) {
        self.setTabView(atIndex: 6)
        NSApp.mainWindow?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Settings")
    }
    
    
    @IBAction func addToBookmarks(_ sender: NSMenuItem) {
        let context = persistentContainer.viewContext
        
        if let splitVC = NSApp.mainWindow?.contentViewController as? NSSplitViewController {
            if let connVC = splitVC.splitViewItems[0].viewController as? ConnectionViewController {
                if let connection = connVC.connection {
                    let bookmark:Bookmark = NSEntityDescription.insertNewObject(
                        forEntityName: "Bookmark", into: context) as! Bookmark

                    bookmark.name = connection.serverInfo.serverName
                    bookmark.hostname = "\(connection.url.hostname):\(connection.url.port)"
                    bookmark.login = connection.url.login
                    
                    let keychain = Keychain(server: "wired://\(bookmark.hostname!)", protocolType: .irc)
                    keychain[bookmark.login!] = connection.url.password
                    
                    self.saveAction(sender)
                    
                    NotificationCenter.default.post(name: .didAddNewBookmark, object: bookmark, userInfo: nil)
                }
            }
        }
    }
    
    
    @IBAction func connectBookmark(_ sender: NSMenuItem) {
        if let bookmark = sender.representedObject as? Bookmark {
            _ = ConnectionWindowController.connectConnectionWindowController(withBookmark: bookmark)
        }
    }
    
    
    @IBAction func preferencesMenuItemActionHandler(_ sender: NSMenuItem) {
        preferencesWindowController.show()
    }
    
    
    
    // MARK: - Menu Delegate
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let item = menu.addItem(withTitle: "Add To Bookmarks", action: #selector(addToBookmarks(_:)), keyEquivalent: "B")
        item.keyEquivalentModifierMask = NSEvent.ModifierFlags.option
        
        menu.addItem(NSMenuItem.separator())
        
        var i = 0
        for bookmark in ConnectionsController.shared.bookmarks() {
            let item = menu.addItem(withTitle: bookmark.name!, action: #selector(connectBookmark), keyEquivalent: "\(i)")
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags.command
            item.representedObject = bookmark
            i += 1
        }
    }
    
    
    // MARK: - Static Connection Helpers
    private static func hasActiveConnections() -> Bool {
        for c in ConnectionsController.shared.connections {
            if let cwc = c.connectionWindowController {
                if cwc.connection != nil && cwc.connection.isConnected() {
                    return true
                }
            }
        }
        return false
    }
    

    public static func showWiredError(_ error:WiredError) {
        let alert = NSAlert()
        alert.messageText = error.title
        alert.informativeText = error.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    
    public static func windowController(forConnection connection:Connection) -> ConnectionWindowController? {
        for c in ConnectionsController.shared.connections {
            if let cwc = c.connectionWindowController {
                if cwc.connection == connection {
                    return cwc
                }
            }
        }
        return nil
    }
    
    
    public static func windowController(forURI URI:String) -> ConnectionWindowController? {
        for c in ConnectionsController.shared.connections {
            if let cwc = c.connectionWindowController {
                if cwc.connection.URI == URI {
                    return cwc
                }
            }
        }
        return nil
    }
    
    
    public static func windowController(forBookmark bookmark:Bookmark) -> ConnectionWindowController? {        
        for c in ConnectionsController.shared.connections {
            if let cwc = c.connectionWindowController {
                if cwc.connection != nil && "\(cwc.connection.url.hostname):\(cwc.connection.url.port)" == bookmark.hostname! && cwc.connection.url.login == bookmark.login! {
                    return cwc
                }
            }
        }
        return nil
    }
    
    
    public static func selectedToolbarIdentifier(forConnection connection: Connection) -> String? {
        if let wc = AppDelegate.windowController(forConnection: connection) {
            return wc.window?.toolbar?.selectedItemIdentifier?.rawValue
        }
        return nil
    }
    
    
    
    public static func incrementChatUnread(withValue count:Int = 1, forConnection connection:Connection) {
        unreadChatMessages += count
                
        AppDelegate.updateBadge(ofItemWithIdentifier: "Chat", withValue: unreadChatMessages, forConnection: connection)
        AppDelegate.updateValueOfTab(forConnection: connection)
        AppDelegate.updateDockBadge()
    }
    
    public static func decrementChatUnread(withValue count:Int = 1, forConnection connection:Connection) {
        unreadChatMessages -= count
                
        AppDelegate.updateBadge(ofItemWithIdentifier: "Chat", withValue: unreadChatMessages, forConnection: connection)
        AppDelegate.updateValueOfTab(forConnection: connection)
        AppDelegate.updateDockBadge()
    }
    
    
    public static func resetChatUnread(forKey key:String, forConnection connection:Connection) {
        unreadChatMessages = 0
        
        AppDelegate.updateBadge(ofItemWithIdentifier: "Chat", withValue: 0, forConnection: connection)
        AppDelegate.updateValueOfTab(forConnection: connection)
        AppDelegate.updateDockBadge()
    }
    
    
    @objc public static func updateUnreadMessages(forConnection connection:Connection) {
        var count = 0
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Message")
        fetchRequest.predicate = NSPredicate(format: "read == %d", false)
        
        if let c = try? AppDelegate.shared.persistentContainer.viewContext.count(for: fetchRequest) {
            count = c
        }
                
        unreadPrivateMessages = count
        
        AppDelegate.updateBadge(ofItemWithIdentifier: "Messages", withValue: unreadPrivateMessages, forConnection: connection)
        AppDelegate.updateValueOfTab(forConnection: connection)
        AppDelegate.updateDockBadge()
    }
    
    
    public static func updateBadge(ofItemWithIdentifier toolbarIdentifier:String, withValue count:Int, forConnection connection:Connection) {
        if let window = AppDelegate.windowController(forConnection: connection)?.window {
            if let toolbar = window.toolbar {
                for item in toolbar.items {
                    if item.itemIdentifier.rawValue == toolbarIdentifier {
                        if count > 0 {
                            item.image = MSCBadgedTemplateImage.image(named: NSImage.Name(toolbarIdentifier), withCount: count)
                        } else {
                            item.image = NSImage(named: toolbarIdentifier)
                        }
                    }
                }
            }
        }
    }
    
    
    public static func updateValueOfTab(forConnection connection:Connection) {
        let total = unreadChatMessages + unreadPrivateMessages
        
        if let window = AppDelegate.windowController(forConnection: connection)?.window as? ConnectionWindow {
            if total > 0 {
                window.tab.attributedTitle = NSAttributedString(string: "(\(total)) \(connection.serverInfo.serverName!)")
            } else {
                window.tab.attributedTitle = NSAttributedString(string: "\(connection.serverInfo.serverName!)")
            }
        }
    }

    
    public static func updateDockBadge() {
        let total = unreadChatMessages + unreadPrivateMessages
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : ""
    }
    
    
    public static func notify(identifier:String, title:String, subtitle:String? = nil, text:String, connection:Connection) {
        let content = UNMutableNotificationContent()

        content.title = title
        content.body = text
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = connection.URI
        
        if let s = subtitle {
            content.subtitle = s
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.add(request) { (error) in
            if let error = error {
                print("Error \(error.localizedDescription)")
            }
        }
    }
    
    
    public static func emoji(forKey key: String) -> String? {
        if let dict = UserDefaults.standard.object(forKey: "WSEmojiSubstitutions") as? [String:String] {
            return dict[key]
        }
        
        return nil
    }
    
    
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == "chatMessage" {
            // find window for URI
            if let window = AppDelegate.windowController(forURI: response.notification.request.content.categoryIdentifier)?.window {
                // select Chat toolbar item
                window.makeKey()
                AppDelegate.shared.perform(#selector(AppDelegate.showChat(_:)), with: self, afterDelay: 0.1)
            }
        } else if response.notification.request.identifier == "privateMessage" {
            if let window = AppDelegate.windowController(forURI: response.notification.request.content.categoryIdentifier)?.window {
                // select Message toolbar item
                window.makeKey()
                AppDelegate.shared.perform(#selector(AppDelegate.showMessages(_:)), with: self, afterDelay: 0.1)
            }
        } else if response.notification.request.identifier == "transferError" {
            if let window = AppDelegate.windowController(forURI: response.notification.request.content.categoryIdentifier)?.window {
                // select Message toolbar item
                window.makeKey()
                AppDelegate.shared.perform(#selector(AppDelegate.showTransfers(_:)), with: self, afterDelay: 0.1)
            }
        }
    }
    
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == "transferError" {
            completionHandler(.alert)
        }
    }
    
    
    // MARK: - Privates
    private func setTabView(withIdentifier identifier:String) {
        
    }
    
    private func setTabView(atIndex index:Int) {
        if let currentWindowController = currentWindowController() {
            if let splitViewController = currentWindowController.contentViewController as? NSSplitViewController {
                if let tabViewController = splitViewController.splitViewItems[1].viewController as? NSTabViewController {
                    tabViewController.selectedTabViewItemIndex = index
                }
            }
        }
    }
    
    private func currentWindowController() -> ConnectionWindowController? {
        if let window = NSApp.mainWindow, let connectionWindowController = window.windowController as? ConnectionWindowController {
            return connectionWindowController
        }
        return nil
    }

    
    
    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentContainer(name: "Wired3")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject?) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        let context = persistentContainer.viewContext

        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)
            }
        }
    }

    func windowWillReturnUndoManager(window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return persistentContainer.viewContext.undoManager
    }


    
    
    private func terminateCoreData(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let context = persistentContainer.viewContext
        
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing to terminate")
            return .terminateCancel
        }
        
        if !context.hasChanges {
            return .terminateNow
        }
        
        do {
            try context.save()
        } catch {
            let nserror = error as NSError

            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .terminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .terminateNow
    }
}

