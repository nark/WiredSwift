//
//  ProfileViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 01/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit

extension Notification.Name {
    static let userDidUpdateProfile  = Notification.Name("userDidUpdateProfile")
}



class ProfileViewController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    @IBOutlet var nickTextField:    UITextField!
    @IBOutlet var statusTextField:  UITextField!
    @IBOutlet var iconImageView:    UIImageView!
    
    public var masterViewController:BookmarksViewController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let image = UserDefaults.standard.image(forKey: "WSUserIcon") {
            self.iconImageView.image = image
        }
        
        if let nick = UserDefaults.standard.value(forKey: "WSUserNick") as? String {
            self.nickTextField.text = nick
        }
        
        if let status = UserDefaults.standard.value(forKey: "WSUserStatus") as? String {
            self.statusTextField.text = status
        }
    }
    
    
    // MARK: -
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        guard let image = info[.editedImage] as? UIImage else {
            print("No image found")
            return
        }

        if let newImage = image.resize(withNewWidth: 64) {
            self.iconImageView.image = newImage
        }
    }


    
    
    // MARK: -
    
    @IBAction func changeIcon(_ sender: Any) {
        let vc = UIImagePickerController()
        vc.sourceType = .photoLibrary
        vc.allowsEditing = true
        vc.delegate = self
        present(vc, animated: true)
    }
    
    
    @IBAction func cancel(_ sender: Any) {
        self.dismiss(animated: true) {  }
    }
    
    @IBAction func ok(_ sender: Any) {
        if let image = self.iconImageView.image {
            UserDefaults.standard.set(image: image, forKey: "WSUserIcon")
        }
        
        if let text = self.nickTextField.text {
            UserDefaults.standard.set(text, forKey: "WSUserNick")
        }
        
        if let text = self.statusTextField.text {
            UserDefaults.standard.set(text, forKey: "WSUserStatus")
        }
        
        self.dismiss(animated: true) {
            NotificationCenter.default.post(name: .userDidUpdateProfile, object: nil)
        }
    }
    
}
