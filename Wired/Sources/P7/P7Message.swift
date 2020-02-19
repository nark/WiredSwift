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
    
    private var parameters: [String:Any] = [:]
    
    
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
        
        self.loadBinaryMessage(data)
    }
    
    
    public func addParameter(field: String, value: Any?) {
        self.parameters[field] = value
    }
    
    
    public func string(forField field: String) -> String? {
        if let str = self.parameters[field] as? String {
            return str.trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }
    
    
    public func data(forField field: String) -> Data? {
        if let data = self.parameters[field] as? Data {
            return data
        }
        return nil
    }
    
    
    public func bool(forField field: String) -> Bool? {
        if let value = self.parameters[field] as? Bool {
            return value
        }
        return nil
    }
    
    
    public func uint32(forField field: String) -> UInt32? {
        if let value = self.parameters[field] as? UInt32 {
            return value
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
        let msg = XMLElement(name: "p7:message")
        let xml = XMLDocument(rootElement: msg)
        
        msg.addAttribute(XMLNode.attribute(withName: "xmlns:p7", stringValue: "http://www.zankasoftware.com/P7/Message") as! XMLNode)
        msg.addAttribute(XMLNode.attribute(withName: "name", stringValue: self.name) as! XMLNode)
        
        for (field, value) in self.parameters {
            let p = XMLElement(name: "p7:field")
            
            if spec.fieldsByName[field]?.type == .string {
                if let string = value as? String {
                    p.setStringValue(string, resolvingEntities: false)
                }
            }
            else if spec.fieldsByName[field]?.type == .int32 ||
                    spec.fieldsByName[field]?.type == .uint32 {
                if let val = value as? UInt32 {
                    p.setStringValue(String(val), resolvingEntities: false)
                }
            }
            // TODO: complete all types
        
            p.addAttribute(XMLNode.attribute(withName: "name", stringValue: field) as! XMLNode)
            msg.addChild(p)
        }
        
        var options = XMLNode.Options.nodePromoteSignificantWhitespace.rawValue
        
        if pretty {
            options = XMLNode.Options.nodePromoteSignificantWhitespace.rawValue | XMLNode.Options.nodePrettyPrint.rawValue
        }
        
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + xml.xmlString(options: XMLNode.Options(rawValue: options)) + "\r\n"
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
                                let str = (value as! String)
                                if let d = str.nullTerminated {
                                    data.append(d)
                                }
                            } else if specField.type == .date { // date (8)
                                let str = (value as! String)
                                if let d = str.data(using: .utf8) {
                                    data.append(d)
                                }
                            } else if specField.type == .data { // data (x)
                                if let d = value as? Data {
                                    let l = UInt32(d.count)
                                    data.append(uint32: l, bigEndian: true)
                                    data.append(d)
                                }
                            } else if specField.type == .oobdata { // oobdata (8)
                                let str = (value as! String)
                                if let d = str.nullTerminated {
                                    data.append(d)
                                }
                            } else if specField.type == .list { // list (x)

                            }
                        }
                    }
                }
            }
        }
        return data
    }
    
    

    
    private func loadXMLMessage(_ xml:String) {
        do {
            let xmlDoc  = try XMLDocument(xmlString: xml)
            let names   = try xmlDoc.nodes(forXPath: "//p7:message/@name")
            
            if let name = names.first?.stringValue {
                self.name = name
                
                if let specMessage = spec.messagesByName[name] {
                    self.specMessage    = specMessage
                    self.id             = specMessage.id
                    
                    let nodes = try xmlDoc.nodes(forXPath: "//p7:message/p7:field")
                    
                    for node in nodes {
                        if let element = node as? XMLElement {
                            if let attribute = element.attribute(forName: "name"), let attrName = attribute.stringValue {
                                self.addParameter(field: attrName, value: element.objectValue)
                            }
                        }
                    }
                } else {
                    Logger.error("ERROR: Unknow message")
                }
            } else {
                Logger.error("ERROR: Missing message name")
            }
            
        } catch {
            Logger.error("ERROR: Cannot parse XML message")
        }
    }
    
    
    
    private func loadBinaryMessage(_ data: Data) {
        var offset = 0
                
        let messageIDData = data.subdata(in: 0..<4)
        
        offset += 4
                
        self.id = String(messageIDData.uint32.bigEndian)
        
        if let specMessage = spec.messagesByID[Int(messageIDData.uint32.bigEndian)] {
            self.name = specMessage.name!
            self.specMessage = specMessage
            
            var fieldIDData:Data!
            var fieldID:Int!
            
            while offset < data.count {
                fieldIDData = data.subdata(in: offset..<offset+4)
                fieldID = Int(fieldIDData.uint32.bigEndian)
                
                offset += 4
                
                if let specField = spec.fieldsByID[fieldID] {
                    var fieldLength = 0
                    
                    //Logger.debug("READ field: \(specField.name) [\(fieldID)]")
                    
                    // read length if needed
                    if specField.type == .string || specField.type == .data || specField.type == .list {
                        let fieldLengthData = data.subdata(in: offset..<offset+4)
                        fieldLength = Int(fieldLengthData.uint32.bigEndian)
                        offset += 4
                    } else {
                        fieldLength = SpecType.size(forType: specField.type)
                    }
                
                    if fieldLength > 0 {
                        // read value
                        let fieldData = data.subdata(in: offset..<offset+fieldLength)
                        
                        if specField.type == .bool {
                            
                        }
                        else if specField.type == .enum32 {
                            
                        }
                        else if specField.type == .int32 {
                            self.addParameter(field: specField.name, value: fieldData.uint32.bigEndian)
                        }
                        else if specField.type == .uint32 {
                            self.addParameter(field: specField.name, value: fieldData.uint32.bigEndian)
                        }
                        else if specField.type == .int64 {
                            
                        }
                        else if specField.type == .uint64 {
                            
                        }
                        else if specField.type == .double {
                            
                        }
                            
                        else if specField.type == .string {
                            if let string = String(bytes: fieldData, encoding: .utf8) {
                                self.addParameter(field: specField.name, value: string)
                            }
                        }
                        else if specField.type == .uuid {
                            
                        }
                        else if specField.type == .date {
                            
                        }
                        else if specField.type == .data {
                            //print(fieldData.toHex())
                            self.addParameter(field: specField.name, value: fieldData)
                        }
                        else if specField.type == .oobdata {
                            
                        }
                        else if specField.type == .list {
                            //print(fieldData.toHex())
                        }
                        
                        // TODO: complete all types
                    }
                    
                    offset += fieldLength
                    
                } else {
                    Logger.error("ERROR : Unknow field ID: \(fieldID)")
                    return
                }
                
            }
        
        } else {
            Logger.error("ERROR : Unknow message ID")
            return
        }
    }
}
