//
//  RootSplitViewController.swift
//  TabBar Test
//
//  Created by Rafael Warnault on 17/04/2020.
//  Copyright © 2020 Rafael Warnault. All rights reserved.
//

import UIKit
import WiredSwift_iOS

class RootSplitViewController: UISplitViewController, UISplitViewControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.delegate = self
    }
    
    
    var bookmark:Bookmark!
    var connection: Connection? {
        didSet {
            // Update the view.
            if let c = self.connection {
                if let navigationController = self.viewControllers[0] as? UINavigationController {
                    if let chatsViewController = navigationController.topViewController as? ChatsViewController {
                        chatsViewController.navigationItem.title = c.serverInfo.serverName
                        chatsViewController.bookmark = self.bookmark
                        chatsViewController.connection = c
                    }
                    else if let boardsViewController = navigationController.topViewController as? BoardsViewController {
                        boardsViewController.navigationItem.title = c.serverInfo.serverName
                        boardsViewController.bookmark = self.bookmark
                        boardsViewController.connection = c
                    }
                }
            }
        }
    }
    
    
                
    // MARK: - Split View Controller Delegate
                
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        return true
    }


}
