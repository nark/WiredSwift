//
//  AppDelegate.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 31/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import WiredSwift_iOS

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, ConnectionDelegate {
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        print("connectionDidReceiveMessage: \(message)")
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        print("connectionDidReceiveError: \(message)")
    }
    



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        // this automatically load P7 and Wired 2.0 specification
        let spec = P7Spec()

        // the Wired URL to connect to
        let url = Url(withString: "wired://192.168.1.23:4871")

        // init connection
        let connection = Connection(withSpec: spec, delegate: self)
        connection.nick = "Me"
        connection.status = "Testing WiredSwift"

        // perform  connect
        if connection.connect(withUrl: url) {
            // connected
        } else {
            // not connected
            print(connection.socket.errors)
        }
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

