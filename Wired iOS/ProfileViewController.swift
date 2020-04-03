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

        guard let image = info[picker.sourceType == .photoLibrary ? .editedImage : .originalImage] as? UIImage else {
            print("No image found")
            return
        }

        if let newImage = image.resize(withNewWidth: 64) {
            self.iconImageView.image = newImage
        }
    }


    
    
    // MARK: -
    
    @IBAction func changeIcon(_ sender: Any) {
        self.openCamera(sender)
    }
    
    private func openCamera(_ sender:Any) {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        
        
        let alert = UIAlertController(title: "Photo", message: "Select below", preferredStyle: .actionSheet)
        
        alert.popoverPresentationController?.sourceView = self.iconImageView
        alert.popoverPresentationController?.permittedArrowDirections = .up
        alert.popoverPresentationController?.sourceRect = CGRect(x: self.iconImageView.frame.size.width/2, y: self.iconImageView.center.y, width: 0, height: 0)

        alert.addAction(UIAlertAction(title: "Take Picture", style: .default, handler: { (action) in
            imagePicker.sourceType = .camera
            self.navigationController!.present(imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { (action) in
            imagePicker.sourceType = .photoLibrary
            self.navigationController!.present(imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        self.navigationController?.present(alert, animated: true, completion: nil)
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
