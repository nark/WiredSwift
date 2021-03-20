//
//  main.swift
//  Client
//
//  Created by Rafael Warnault on 19/03/2021.
//

import Foundation
import WiredSwift

Logger.setMaxLevel(.VERBOSE)

let specURL     = URL(string: "https://wired.read-write.fr/wired.xml")!
let serverURL   = Url(withString: "wired://admin:admin@127.0.0.1")

guard let spec  = P7Spec(withUrl: specURL) else {
    exit(-111)
}

let connection  = Connection(withSpec: spec, delegate: nil)

let ok = connection.connect(withUrl: serverURL, cipher: .RSA_AES_256_SHA256, checksum: .SHA256)

print(ok)

sleep(400)
