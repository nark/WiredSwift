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



class ProfileViewController: UITableViewController  {
    @IBOutlet var nickTextField:    UITextField!
    @IBOutlet var statusTextField:  UITextField!
    @IBOutlet var iconImageView:    UIImageView!
    
    public var masterViewController:BookmarksViewController!
    
    let imagePicker = UIImagePickerController()
        
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
    
    @IBAction func changeIcon(_ sender: Any) {
        self.openCamera(sender)
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
    
    
    
    // MARK: -
    private func openCamera(_ sender:Any) {
        self.imagePicker.delegate = self
        //self.imagePicker.allowsEditing = true
        self.imagePicker.mediaTypes = ["public.image"]
        self.imagePicker.navigationBar.barStyle = .default
        
        var style = UIAlertController.Style.alert
        
        if #available(iOS 13.0, *) {
            style = .actionSheet
        }
        
        let alert = UIAlertController(title: NSLocalizedString("Photo", comment: "Image Picker Alert Title"), message: NSLocalizedString("Select below", comment: "Image Picker Alert Message"), preferredStyle: style)
        
        alert.popoverPresentationController?.sourceView = self.iconImageView
        alert.popoverPresentationController?.permittedArrowDirections = .up
        alert.popoverPresentationController?.sourceRect = CGRect(x: self.iconImageView.frame.size.width/2, y: self.iconImageView.center.y, width: 0, height: 0)

        alert.addAction(UIAlertAction(title: NSLocalizedString("Take Picture", comment: "Image Picker Take Picture Button"), style: .default, handler: { (action) in
            self.imagePicker.sourceType = .camera
            self.navigationController!.present(self.imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Photo Library", comment: "Image Picker Photo Library Button"), style: .default, handler: { (action) in
            self.imagePicker.sourceType = .photoLibrary
            self.navigationController!.present(self.imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Image Picker Cancel Button"), style: .cancel, handler: nil))
        
        self.navigationController?.present(alert, animated: true, completion: nil)
    }
    
    
    private func pickerController(_ controller: UIImagePickerController, didSelect image: UIImage?) {
        controller.dismiss(animated: true, completion: nil)
        
        if let i = image?.scale(with: CGSize(width: 64.0, height: 64.0)) {
            self.iconImageView.image = i
        }
    }
}


extension ProfileViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate & UIPopoverControllerDelegate {
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.pickerController(picker, didSelect: nil)
    }

    public func imagePickerController(_ picker: UIImagePickerController,
                                      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.originalImage] as? UIImage else {
            return self.pickerController(picker, didSelect: nil)
        }
        
        self.pickerController(picker, didSelect: image)
    }
}
