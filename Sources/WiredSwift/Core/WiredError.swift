//
//  WiredError.swift
//  Wired
//
//  Created by Rafael Warnault on 17/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

public class WiredError: NSObject, Error {
    public var specError:SpecError?

    private var errorTitle:String
    private var errorMessage:String
    
    
    public init(withSPecError specError: SpecError) {
        self.specError = specError
        
        if let se = self.specError {
            errorTitle = se.name
            errorMessage = se.description
        } else {
            errorTitle = "Unknown error"
            errorMessage = "Unknown error message"
        }
    }
    
    
    public init(withTitle title:String, message: String) {
        self.errorTitle = title
        self.errorMessage = message
    }
    
    
    public init(message: P7Message) {
        self.errorTitle = "Server Error"
        self.errorMessage = message.string(forField: "wired.error.string") ?? "No error message"
    }
    
    
    public override var description: String {
        return "\(self.errorTitle): \(self.errorMessage)"
    }
    
    
    public var title:String {
        self.errorTitle
    }
    
    
    public var message:String {
        self.errorMessage
    }
}
