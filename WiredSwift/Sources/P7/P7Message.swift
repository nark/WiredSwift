//
//  Message.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation



/**
 This class handles messages of the Wired protocol. A message can
 be created empty for specification name, loaded from XML string or
 serialized Data object. The class provides a set of tools to manipulate
 messages and their data in those various formats.

@author Rafaël Warnault (mailto:dev@read-write.fr)
*/
public class P7Message: NSObject {
    public var id: String!
    public var name: String!
    public var spec: P7Spec!
    public var specMessage: SpecMessage!
    public var size:Int = 0
    
    private var parameters: [String:Any] = [String:Any](minimumCapacity: 50)
    
    public var numberOfParameters:Int {
        get {
            return self.parameters.count
        }
    }
    public var parameterKeys:[String] {
        get {
            return Array(self.parameters.keys)
        }
    }
    
    
    public init(withName name: String, spec: P7Spec) {
        if let specMessage = spec.messagesByName[name] {
            self.specMessage    = specMessage
            self.id             = specMessage.attributes["id"] as? String
            self.name           = name
            self.spec           = spec
        }
    }

    
    public init(withXML xml: String, spec: P7Spec) {
        super.init()
        
        self.spec = spec
        
        self.loadXMLMessage(xml)
    }
    
    
    public init(withData data: Data, spec: P7Spec) {
        super.init()
        
        self.spec = spec
        self.size = data.count
        
        self.loadBinaryMessage(data)
    }
    
    
    public func addParameter(field: String, value: Any?) {
        self.parameters[field] = value
    }
    
    
    public func lazy(field: String) -> String? {
        let value = self.parameters[field]
        
        if  spec.fieldsByName[field]?.type == .string ||
            spec.fieldsByName[field]?.type == .uuid {
            if let string = value as? String {
                return string
            }
        }
        else if spec.fieldsByName[field]?.type == .int32 ||
                spec.fieldsByName[field]?.type == .uint32 {
            if let val = value as? UInt32 {
                return String(val)
            }
        }
        else if spec.fieldsByName[field]?.type == .int64 ||
                spec.fieldsByName[field]?.type == .uint64 {
            if let val = value as? UInt64 {
                return String(val)
            }
        }
        else if spec.fieldsByName[field]?.type == .data {
            if let val = value as? Data {
                return val.toHex()
            }
        }
        else if spec.fieldsByName[field]?.type == .oobdata {
            if let val = value as? Data {
                return val.toHex()
            }
        }
        // TODO: complete all types
        return nil
    }
    
    
    public func string(forField field: String) -> String? {
        if let str = self.parameters[field] as? String {
            return str.trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }
    
    public func uuid(forField field: String) -> String? {
        if let str = self.parameters[field] as? String {
            return str
        }
        return nil
    }
    
    
    public func data(forField field: String) -> Data? {
        if let data = self.parameters[field] as? Data {
            return data
        }
        return nil
    }
    
    
    public func date(forField field: String) -> Date? {        
        if let value = self.parameters[field] as? Double {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }
    
    
    public func bool(forField field: String) -> Bool? {
        if let value = self.parameters[field] as? UInt8 {
            return value == 1 ? true : false
        }
        return nil
    }
    
    
    public func uint32(forField field: String) -> UInt32? {
        if let value = self.parameters[field] as? UInt32 {
            return value
        }
        return nil
    }
    
    public func uint64(forField field: String) -> UInt64? {        
        if let value = self.parameters[field] as? Data {
            return value.uint64
        }
        return nil
    }
    
    public func enumeration(forField field: String) -> UInt32? {
        if let value = self.parameters[field] as? UInt32 {
            return value
        }
        return nil
    }
    
    
    public func xml(pretty: Bool = false) -> String {
        return "TODO: reimplement with AEXML"
        
//        let msg = XMLElement(name: "p7:message")
//        let xml = XMLDocument(rootElement: msg)
//
//        msg.addAttribute(XMLNode.attribute(withName: "xmlns:p7", stringValue: "http://www.zankasoftware.com/P7/Message") as! XMLNode)
//        msg.addAttribute(XMLNode.attribute(withName: "name", stringValue: self.name) as! XMLNode)
//
//        for (field, value) in self.parameters {
//            let p = XMLElement(name: "p7:field")
//
//            if spec.fieldsByName[field]?.type == .string {
//                if let string = value as? String {
//                    p.setStringValue(string, resolvingEntities: false)
//                }
//            }
//            else if spec.fieldsByName[field]?.type == .int32 ||
//                    spec.fieldsByName[field]?.type == .uint32 {
//                if let val = value as? UInt32 {
//                    p.setStringValue(String(val), resolvingEntities: false)
//                }
//            }
//            else if spec.fieldsByName[field]?.type == .int64 ||
//                    spec.fieldsByName[field]?.type == .uint64 {
//                if let val = value as? UInt64 {
//                    p.setStringValue(String(val), resolvingEntities: false)
//                }
//            }
//            else if spec.fieldsByName[field]?.type == .data {
//                if let val = value as? Data {
//                    p.setStringValue(val.toHex(), resolvingEntities: false)
//                }
//            }
//            else if spec.fieldsByName[field]?.type == .oobdata {
//                if let val = value as? Data {
//                    p.setStringValue(val.toHex(), resolvingEntities: false)
//                }
//            }
//            // TODO: complete all types
//
//            p.addAttribute(XMLNode.attribute(withName: "name", stringValue: field) as! XMLNode)
//            msg.addChild(p)
//        }
//
//        var options = XMLNode.Options.nodePromoteSignificantWhitespace.rawValue
//
//        if pretty {
//            options = XMLNode.Options.nodePromoteSignificantWhitespace.rawValue | XMLNode.Options.nodePrettyPrint.rawValue
//        }
//
//        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + xml.xmlString(options: XMLNode.Options(rawValue: options)) + "\r\n"
    }
    
    
    
    public func bin() -> Data {
        var data = Data()
                
        // append message ID
        if let messageID = UInt32(self.id) {
            data.append(uint32: messageID, bigEndian: true)
            
            // append fields
            for (field, value) in self.parameters {
                if let specField = spec.fieldsByName[field] {
                    
                    if let fieldIDStr = specField.id {
                        // append field ID
                        if let fieldID = UInt32(fieldIDStr) {
                            data.append(uint32: fieldID, bigEndian: true)
                            
                            // append value
                            if specField.type == .bool { // boolean (1)
                                let v = (value as? Bool) == true ? UInt8(1) : UInt8(0)
                                data.append(uint8: v, bigEndian: true)
                                
                            } else if specField.type == .enum32 { // enum (4)
                                data.append(uint32: value as! UInt32, bigEndian: true)
                                
                            } else if specField.type == .int32 { // int32 (4)
                                data.append(uint32: value as! UInt32, bigEndian: true)
                                
                            } else if specField.type == .uint32 { // uint32 (4)
                                data.append(uint32: value as! UInt32, bigEndian: true)
                                
                            } else if specField.type == .int64 { // int64 (4)
                                data.append(uint64: value as! UInt64, bigEndian: true)
                                
                            } else if specField.type == .uint64 { // uint64 (4)
                                data.append(uint64: value as! UInt64, bigEndian: true)
                                
                            } else if specField.type == .double { // double (4)
                                data.append(double: value as! Double, bigEndian: true)
                                
                            } else if specField.type == .string { // string (x)
                                if let str = value as? String {
                                    if let d = str.nullTerminated {
                                        let l = UInt32(d.count)
                                        data.append(uint32: l, bigEndian: true)
                                        data.append(d)
                                    }
                                }
                            } else if specField.type == .uuid { // uuid (16)
                                if let str = value as? String {
                                    var buffer:Array<UInt8> = Array<UInt8>()
                                    if let uuid = NSUUID(uuidString: str) {
                                        uuid.getBytes(&buffer)
                                        data.append(Data(bytes: &buffer, count: 16))
                                    }
                                }
                            } else if specField.type == .date { // date (8)

                            } else if specField.type == .data { // data (x)
                                if let d = value as? Data {
                                    let l = UInt32(d.count)
                                    data.append(uint32: l, bigEndian: true)
                                    data.append(d)
                                }
                            } else if specField.type == .oobdata { // oobdata (8)
                                if let d = value as? Data {
                                    data.append(d)
                                }
                            } else if specField.type == .list { // list (x)

                            }
                        }
                    }
                }
            }
        }
        
        self.size = data.count
        
        return data
    }
    
    

    
    private func loadXMLMessage(_ xml:String) {
        print("TODO: reimplement with AEXML")
//        do {
//            let xmlDoc  = try XMLDocument(xmlString: xml)
//            let names   = try xmlDoc.nodes(forXPath: "//p7:message/@name")
//
//            if let name = names.first?.stringValue {
//                self.name = name
//
//                if let specMessage = spec.messagesByName[name] {
//                    self.specMessage    = specMessage
//                    self.id             = specMessage.id
//
//                    let nodes = try xmlDoc.nodes(forXPath: "//p7:message/p7:field")
//
//                    for node in nodes {
//                        if let element = node as? XMLElement {
//                            if let attribute = element.attribute(forName: "name"), let attrName = attribute.stringValue {
//                                self.addParameter(field: attrName, value: element.objectValue)
//                            }
//                        }
//                    }
//                } else {
//                    Logger.error("ERROR: Unknow message")
//                }
//            } else {
//                Logger.error("ERROR: Missing message name")
//            }
//
//        } catch {
//            Logger.error("ERROR: Cannot parse XML message")
//        }
    }
    
    
    
    private func loadBinaryMessage(_ data: Data) {
        var offset = 0
                
        let messageIDData = data.subdata(in: 0..<4)
        
        offset += 4
                
        if let v = messageIDData.uint32 {
            self.id = String(v)
        } else {
            Logger.error("ERROR : Cannot read message ID")
            return
        }
        
        if let specMessage = spec.messagesByID[Int(messageIDData.uint32!)] {
            self.name = specMessage.name!
            self.specMessage = specMessage
            
            var fieldIDData:Data!
            var fieldID:Int!
            
            while offset < data.count {
                fieldIDData = data.subdata(in: offset..<offset+4)
                
                if let v = fieldIDData.uint32 {
                    fieldID = Int(v)
                } else {
                    Logger.error("ERROR : Cannot read field ID")
                    return
                }
                
                offset += 4
                
                if let specField = spec.fieldsByID[fieldID] {
                    var fieldLength = 0
                    
                    //Logger.debug("READ field: \(specField.name) [\(fieldID)]")
                    
                    // read length if needed
                    if specField.type == .string || specField.type == .data || specField.type == .list {
                        let fieldLengthData = data.subdata(in: offset..<offset+4)
                        fieldLength = Int(fieldLengthData.uint32!)
                        offset += 4
                    } else {
                        fieldLength = SpecType.size(forType: specField.type)
                    }
                
                    if fieldLength > 0 {
                        // read value
                        let fieldData = data.subdata(in: offset..<offset+fieldLength)
                        
                        if specField.type == .bool {
                            self.addParameter(field: specField.name, value: fieldData.uint8.bigEndian)
                        }
                        else if specField.type == .enum32 {
                            // self.addParameter(field: specField.name, value: fieldData.uint32.bigEndian)
                        }
                        else if specField.type == .int32 {
                            self.addParameter(field: specField.name, value: fieldData.uint32)
                        }
                        else if specField.type == .uint32 {
                            self.addParameter(field: specField.name, value: fieldData.uint32)
                        }
                        else if specField.type == .int64 {
                            self.addParameter(field: specField.name, value: fieldData.uint64)
                        }
                        else if specField.type == .uint64 {
                            self.addParameter(field: specField.name, value: fieldData)
                        }
                        else if specField.type == .double {
                            self.addParameter(field: specField.name, value: fieldData.double)
                        }
                        else if specField.type == .string {
                            self.addParameter(field: specField.name, value: String(bytes: fieldData, encoding: .utf8))
                        }
                        else if specField.type == .uuid {
                            self.addParameter(field: specField.name, value: NSUUID(uuidBytes: fieldData.bytes).uuidString)
                        }
                        else if specField.type == .date {
                            self.addParameter(field: specField.name, value: fieldData.double)
                        }
                        else if specField.type == .data {
                            self.addParameter(field: specField.name, value: fieldData)
                        }
                        else if specField.type == .oobdata {
                            self.addParameter(field: specField.name, value: fieldData)
                        }
                        else if specField.type == .list {
                            //print(fieldData.toHex())
                        }
                        
                        // TODO: complete all types
                    }
                    
                    offset += fieldLength
                    
                } else {
                    Logger.error("ERROR : Unknow field ID: \(String(describing: fieldID))")
                    return
                }
                
            }
        
        } else {
            Logger.error("ERROR : Unknow message ID")
            return
        }
    }
}
