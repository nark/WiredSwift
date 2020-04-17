//
//  WiredError.swift
//  Wired
//
//  Created by Rafael Warnault on 17/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

public class WiredError: NSObject {
    public var specError:SpecError?

    private var errorTitle:String!
    private var errorMessage:String!
    
    
    init(withSPecError specError: SpecError) {
        self.specError = specError
    }
    
    
    init(withTitle title:String, message: String) {
        self.errorTitle = title
        self.errorMessage = message
    }
    
    
    public override var description: String {
        if let se = self.specError {
            return se.name
        }
        else {
            return "\(String(describing: self.errorTitle)): \(String(describing: self.errorMessage))"
        }
    }
    
    
    public var title:String {
        get {
            if let se = self.specError {
                return se.name
            }
            else {
                return self.errorTitle
            }
        }
    }
    
    
    public var message:String {
        get {
            if let se = self.specError {
                return se.name
            }
            else {
                return self.errorMessage
            }
        }
    }
}
