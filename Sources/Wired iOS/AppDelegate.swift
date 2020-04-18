//
//  AppDelegate.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 31/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import CoreData
import WiredSwift_iOS
import Reachability
import JGProgressHUD


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    public static let shared:AppDelegate = UIApplication.shared.delegate as! AppDelegate
    public static let dateTimeFormatter = DateFormatter()
    
    var window:UIWindow?
    let hud = JGProgressHUD(style: .dark)
    
    override init() {
        super.init()
        
        self.setupAppearance()
        self.setupUserDefaults()
        
        AppDelegate.dateTimeFormatter.dateStyle = .medium
        AppDelegate.dateTimeFormatter.timeStyle = .medium
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // really needed?
        self.window?.makeKeyAndVisible()
        
        // deal with first launch
        if UserDefaults.standard.bool(forKey: "WSFirstLaunch") == true {
            // show onboarding view
            let storyboard = UIStoryboard.init(name: "Main", bundle: nil)
            if let onboarding = storyboard.instantiateViewController(withIdentifier: "OnboardingViewController") as? OnboardingViewController {
                onboarding.modalPresentationStyle = .fullScreen
                self.window?.rootViewController?.present(onboarding, animated: false, completion: { })
            }
            UserDefaults.standard.set(false, forKey: "WSFirstLaunch")
        }
        
        Logger.setMaxLevel(.INFO)
        
        if let splitViewController = window!.rootViewController as? UISplitViewController {
            splitViewController.preferredDisplayMode = UISplitViewController.DisplayMode.primaryOverlay
        }
        
        return true
    }
    
    
    // MARK: - Connection Helpers
    public var currentConnection:Connection? {
        if let ctbc = AppDelegate.shared.window?.rootViewController as? ConnectionTabBarController {
            return ctbc.connection
        }
        
        return nil
    }
    
    public func connect(withBookmark bookmark:Bookmark,
                        inViewController vc: UIViewController,
                        connectionDelegate:ConnectionDelegate?,
                        completion: ((_ connection:Connection) -> Void)?) {
        
      let spec = P7Spec()
      let url = bookmark.url()
      
      let connection = Connection(withSpec: spec, delegate: connectionDelegate)
      connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? "Swift iOS"
      connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? "Around"
      
      if let b64string = UserDefaults.standard.image(forKey: "WSUserIcon")?.pngData()?.base64EncodedString() {
          connection.icon = b64string
      }
          
        AppDelegate.shared.hud.show(in: vc.view)
      
      // perform  connect
      DispatchQueue.global().async {
          if connection.connect(withUrl: url) {
              DispatchQueue.main.async {
                  AppDelegate.shared.hud.dismiss(afterDelay: 1.0)
                  
                  ConnectionsController.shared.connections[bookmark] = connection

                  if let ctbc = AppDelegate.shared.window?.rootViewController as? ConnectionTabBarController {
                      ctbc.bookmark = bookmark
                      ctbc.connection = connection
                  }

                  // update bookmark with server name
                  bookmark.name = connection.serverInfo.serverName
                  AppDelegate.shared.saveContext()
                  
                completion?(connection)
              }
              
          } else {
              DispatchQueue.main.async {
                  AppDelegate.shared.hud.dismiss(afterDelay: 1.0)
                  
                  let alertController = UIAlertController(
                      title: NSLocalizedString("Connection Error", comment: "Connection Error Alert Title"),
                      message: String(format: NSLocalizedString("Enable to connect to %@", comment: "Connection Error Alert Message"), bookmark.hostname!),
                      preferredStyle: .alert)
                  
                  alertController.addAction(UIAlertAction(
                      title: NSLocalizedString("OK", comment: "Connection Error Alert Button"),
                      style: .default))

                  vc.present(alertController, animated: true) {
                     completion?(connection)
                    }
                }
            }
        }
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
            if let error = error as NSError? {
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
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving support

    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }

    

    
    
    // MARK: - Private
    
    private func setupAppearance() {
        UIButton.appearance().tintColor = UIColor.systemGreen
        UIBarButtonItem.appearance().tintColor = UIColor.systemGreen
        UITabBar.appearance().tintColor = UIColor.systemGreen
    }
    
    
    
    private func setupUserDefaults() {
        // Default preferences
        UserDefaults.standard.register(defaults: [
            "WSUserNick": "WiredSwift",
            "WSUserStatus": "Share The Wealth",
            "WSFirstLaunch": true
        ])
        
        if UserDefaults.standard.image(forKey: "WSUserIcon") == nil {
            if let image = UIImage(named: "DefaultIcon") {
                UserDefaults.standard.set(image: image, forKey: "WSUserIcon")
            }
        }
        
        UserDefaults.standard.synchronize()
    }
}

