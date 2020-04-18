//
//  ConnectionTabBarController.swift
//  Wired
//
//  Created by Rafael Warnault on 17/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import WiredSwift_iOS

class ConnectionTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    var bookmark:Bookmark!
    var connection: Connection? {
        didSet {
            // Update the view.
            if let c = self.connection {
                if c.isConnected() {
                    // propagate connection
                    for vc in self.viewControllers! {
                        if let svc = vc as? RootSplitViewController {
                            svc.bookmark = self.bookmark
                            svc.connection = c
                        }
                    }
                }
            }
        }
    }
}
