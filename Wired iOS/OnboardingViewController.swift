//
//  OnboardingViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 06/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit

extension Notification.Name {
    static let shouldOpenNewConnection = Notification.Name("shouldOpenNewConnection")
}


class OnboardingViewController: UIViewController {
    @IBOutlet var nickTextField:    UITextField!
    @IBOutlet var iconImageView:    UIImageView!
    @IBOutlet var cameraButton:    UIButton!
    @IBOutlet var keyboardHeightLayoutConstraint: NSLayoutConstraint?
    
    let imagePicker = UIImagePickerController()

    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let image = UserDefaults.standard.image(forKey: "WSUserIcon") {
            self.iconImageView.image = image
        }
        
        if let nick = UserDefaults.standard.value(forKey: "WSUserNick") as? String {
            self.nickTextField.text = nick
        }
        
        self.cameraButton.tintColor = UIColor.white
        
        NotificationCenter.default.addObserver(self,
        selector: #selector(self.keyboardNotification(notification:)),
        name: UIResponder.keyboardWillChangeFrameNotification,
        object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func keyboardNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            let endFrameY = endFrame?.origin.y ?? 0
            let duration:TimeInterval = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
            let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
            let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
            let animationCurve:UIView.AnimationOptions = UIView.AnimationOptions(rawValue: animationCurveRaw)
            if endFrameY >= UIScreen.main.bounds.size.height {
                self.keyboardHeightLayoutConstraint?.constant = 0.0
            } else {
                if let f = endFrame {
                    self.keyboardHeightLayoutConstraint?.constant = f.size.height-(f.size.height*1.1)
                } else {
                    self.keyboardHeightLayoutConstraint?.constant = 0.0
                }
            }
            UIView.animate(withDuration: duration,
                                       delay: TimeInterval(0),
                                       options: animationCurve,
                                       animations: { self.view.layoutIfNeeded() },
                                       completion: nil)
        }
    }

    // MARK: -
    
    @IBAction func changeIcon(_ sender: Any) {
        self.openCamera(sender)
    }
    
    @IBAction func newConnection(_ sender: Any) {
        self.save()
        
        self.dismiss(animated: true) {
            
        }
        
        NotificationCenter.default.post(name: .shouldOpenNewConnection, object: nil)
    }
    
    
    @IBAction func cancel(_ sender: Any) {
        self.save()
        self.dismiss(animated: true) {  }
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
            self.present(self.imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Photo Library", comment: "Image Picker Photo Library Button"), style: .default, handler: { (action) in
            self.imagePicker.sourceType = .photoLibrary
            self.present(self.imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Image Picker Cancel Button"), style: .cancel, handler: nil))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    

    
    private func save() {
        if let image = self.iconImageView.image {
            UserDefaults.standard.set(image: image, forKey: "WSUserIcon")
        }
        
        if let text = self.nickTextField.text {
            UserDefaults.standard.set(text, forKey: "WSUserNick")
        }
        
        self.dismiss(animated: true) {
            NotificationCenter.default.post(name: .userDidUpdateProfile, object: nil)
        }
    }
    
    
    private func pickerController(_ controller: UIImagePickerController, didSelect image: UIImage?) {
        controller.dismiss(animated: true, completion: nil)
        
        if let i = image?.scale(with: CGSize(width: 64.0, height: 64.0)) {
            self.iconImageView.image = i
        }
    }

}


extension OnboardingViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate & UIPopoverControllerDelegate {
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
