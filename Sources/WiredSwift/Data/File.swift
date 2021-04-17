//
//  File.swift
//  Server
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation


public class File {
    public static let wiredFileMetaType:String          = "/.wired/type"
    public static let wiredFileMetaComments:String      = "/.wired/comments"
    public static let wiredFileMetaPermissions:String   = "/.wired/permissions"
    public static let wiredFileMetaLabels:String        = "/.wired/labels"
    
    public static let wiredPermissionsFieldSeparator    = "\u{1C}"
    
    public enum FileType: UInt32 {
        case file       = 0
        case directory  = 1
        case uploads    = 2
        case dropbox    = 3
        
        
        public static func set(type: File.FileType, path: String) -> Bool {
            var isDir:ObjCBool = false
            
            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                return false
            }
            
            let typePath = path.stringByAppendingPathComponent(path: wiredFileMetaType)
            let typeData = String(Int(type.rawValue)).data(using: .utf8)
            
            do {
                try typeData?.write(to: URL.init(fileURLWithPath: typePath))
            } catch {
                print(error)
                return false
            }

            return true
        }
        
        public static func type(path: String) -> FileType? {
            var isDir:ObjCBool = false
            var type:FileType? = .file
            
            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                return nil
            }
            
            if isDir.boolValue == true {
                type = .directory
            }
            
            let typePath = path.stringByAppendingPathComponent(path: wiredFileMetaType)
            isDir = false
            
            if !FileManager.default.fileExists(atPath: typePath, isDirectory: &isDir) {
                return type
            }
            
            let typeData = FileManager.default.contents(atPath: typePath)
            
            if  let typeString = typeData?.stringUTF8,
                let value = UInt32(typeString) {
                type = FileType(rawValue: value)
            }
            
            return type
        }
    }
    
    
    public struct FilePermissions: OptionSet {
        public let rawValue: UInt32
        
        public init(rawValue:UInt32 ) {
            self.rawValue = rawValue
        }
        
        public static let ownerWrite       = FilePermissions(rawValue: 2 << 6)
        public static let ownerRead        = FilePermissions(rawValue: 4 << 6)
        public static let groupWrite       = FilePermissions(rawValue: 2 << 3)
        public static let groupRead        = FilePermissions(rawValue: 4 << 3)
        public static let everyoneRead     = FilePermissions(rawValue: 2 << 0)
        public static let everyoneWrite    = FilePermissions(rawValue: 4 << 0)
    }
    
    
    public enum FileLabel: UInt32 {
        case LABEL_NONE     = 0
        case LABEL_RED
        case LABEL_ORANGE
        case LABEL_YELLOW
        case LABEL_GREEN
        case LABEL_BLUE
        case LABEL_PURPLE
        case LABEL_GRAY
    }
    
    
    public static func isValid(path:String) -> Bool {
        if path.hasPrefix(".") {
            return false
        }
        
        if path.contains("/..") {
            return false
        }
        
        if path.contains("../") {
            return false
        }
        
        return true
    }
    
    
    public static func size(path: String) -> UInt64 {
        return FileManager.sizeOfFile(atPath: path) ?? 0
    }
    
    public static func count(path: String) -> UInt32 {
        var isDir:ObjCBool = false
        
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return 0
        }
        
        if !isDir.boolValue {
            return 0
        }
        
        var content:[String] = []
        
        do {
            content = try FileManager.default.contentsOfDirectory(atPath: path)
            content = content.filter({ (string) -> Bool in
                !string.hasPrefix(".")
            })
        } catch {
            return 0
        }
        
        return UInt32(content.count)
    }
}


public class FilePrivilege {
    public var owner:String?
    public var group:String?
    public var mode:File.FilePermissions?
    
    
    public init(owner:String, group:String, mode:File.FilePermissions) {
        self.owner = owner
        self.group = group
        self.mode = mode
    }
    

    public init?(path: String) {
        var isDir:ObjCBool = false
        
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return nil
        }
        
        if !isDir.boolValue {
            return nil
        }
                
        guard let data = FileManager.default.contents(atPath: path.stringByAppendingPathComponent(path: File.wiredFileMetaPermissions)) else {
            return nil
        }
                
        guard let string = data.stringUTF8 else {
            return nil
        }
        
        let components = string.split(separator: Character(File.wiredPermissionsFieldSeparator), omittingEmptySubsequences: false)
                
        self.owner  = String(components.first!)
        self.group  = String(components[1])
        self.mode   = File.FilePermissions(rawValue: UInt32(String(components[2])) ?? 0)
    }
    
    
    public static func set(privileges:FilePrivilege, path:String) -> Bool {
        var isDir:ObjCBool = false
        
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return false
        }
        
        let permissionsPath = path.stringByAppendingPathComponent(path: File.wiredFileMetaPermissions)
                
        let string1 = privileges.owner ?? ""
        let string2 = privileges.group ?? ""
        let string3 = (privileges.mode != nil) ? String(Int(privileges.mode!.rawValue)) : "0"
        
        let array:[String] = [string1, string2, string3]
        let final = array.joined(separator: File.wiredPermissionsFieldSeparator)
        let data = final.data(using: .utf8)
        
        do {
            try data?.write(to: URL.init(fileURLWithPath: permissionsPath))
        } catch {
            print(error)
            return false
        }

        return true
    }
}
