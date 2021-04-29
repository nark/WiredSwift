//
//  Config.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 28/04/2021.
//

import Foundation


public class Config {
    private var config:[String:[String:Any]] = [:]
    private var path:String
    
    public init(withPath path:String) {
        self.path = path
    }
    
    
    public func load() -> Bool {
        do {
            let contents = try String(contentsOfFile: path)
            let lines = contents.split(separator:"\n")
            var section:String? = nil
            
            for line in lines {
                if line.count == 0 {
                    continue
                }
                
                // current section
                if line.hasPrefix("[") && line.hasSuffix("]") {
                    section = String(line)
                    
                    if config[section!] == nil {
                        config[section!] = [:]
                    }
                    
                    continue
                }
                
                if section != nil {
                    let comps = line.split(separator: "=")
                    
                    if comps.count == 2 {
                        config[section!]![comps[0].trimmingCharacters(in: .whitespaces)] = comps[1].trimmingCharacters(in: .whitespaces)
                    } else if comps.count == 1 {
                        config[section!]![comps[0].trimmingCharacters(in: .whitespaces)] = nil
                    } else {
                        Logger.warning("Invalid entry in config file \(path)")
                    }
                }
            }
        } catch let error {
            Logger.error("Cannot load config file \(path) \(error)")
            return false
        }
        
        return true
    }
    
    @discardableResult
    public func save() -> Bool {
        var string:String = ""
        
        for (section, dict) in self.config {
            string += section + "\n"
            for (k,v) in dict {
                string += "\(k) = \(v)" + "\n"
            }
            string += "\n"
        }
        
        do {
            try string.write(to: URL(fileURLWithPath: self.path), atomically: true, encoding: .utf8)
        } catch let error {
            Logger.error("Cannot save config file \(path) \(error)")
            return false
        }
        
        return true
    }
    
    
    public subscript(section:String, key: String) -> Any? {
        get {
            return config["[\(section)]"]![key]
        }
        set(newValue) {
            config["[\(section)]"]![key] = newValue
            
            self.save()
        }
    }
}
