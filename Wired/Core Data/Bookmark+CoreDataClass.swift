//
//  Bookmark+CoreDataClass.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//
//

import Foundation
import CoreData
import KeychainAccess

#if os(iOS)
import WiredSwift_iOS
#else
import WiredSwift
#endif

@objc(Bookmark)
public class Bookmark: NSManagedObject {
    
    public func url() -> Url {
        let keychain = Keychain(server: "wired://\(self.hostname!)", protocolType: .irc)
        let url = Url(withString: "wired://\(self.hostname!)")
        
        url.login = self.login ?? "guest"
        url.password = keychain[url.login] ?? ""
        
        return url
    }
}
