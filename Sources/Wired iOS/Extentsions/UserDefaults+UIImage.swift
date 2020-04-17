//
//  UserDefaults+UIImage.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 02/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit

extension UserDefaults {
    func image(forKey key: String) -> UIImage? {
        var image: UIImage?
        if let imageData = data(forKey: key) {
            image = try! NSKeyedUnarchiver.unarchivedObject(ofClass: UIImage.self, from: imageData)
        }
        return image
    }
    func set(image: UIImage?, forKey key: String) {
        var imageData: NSData?
        if let image = image {
            imageData = try! NSKeyedArchiver.archivedData(withRootObject: image, requiringSecureCoding: false) as NSData
        }
        set(imageData, forKey: key)
    }
}
