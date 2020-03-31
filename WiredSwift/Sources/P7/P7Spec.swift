//
//  Spec.swift
//  Wired
//
//  Created by Rafael Warnault on 17/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
import AEXML

public class SpecItem : NSObject {
    public var spec: P7Spec!
    public var name: String!
    public var id: String!
    public var version: String?
    public var attributes: [String : Any] = [:]
    
    public init(name: String, spec: P7Spec, attributes: [String : Any]) {
        self.spec       = spec
        self.name       = name
        self.id         = attributes["id"] as? String
        self.version    = attributes["version"] as? String
        self.attributes = attributes
    }
    
    public override var description: String {
        return "[\(self.id!)] \(self.name!)"
    }
}



public enum SpecType : UInt32 {
    case bool    = 1
    case enum32  = 2
    case int32   = 3
    case uint32  = 4
    case int64   = 5
    case uint64  = 6
    case double  = 7
    case string  = 8
    case uuid    = 9
    case date    = 10
    case data    = 11
    case oobdata = 12
    case list    = 13
    
    
    public static func specType(forString: String) -> SpecType {
        switch forString {
        case "bool":
            return .bool
        case "enum32":
            return .enum32
        case "int32":
            return .int32
        case "uint32":
            return .uint32
        case "int64":
            return .int64
        case "uint64":
            return .uint64
        case "double":
            return .double
        case "string":
            return .string
        case "uuid":
            return .uuid
        case "date":
            return .date
        case "data":
            return .data
        case "oobdata":
            return .oobdata
        case "list":
            return .list
        default:
            return .uint32
        }
    }
    
    public static func size(forType: SpecType) -> Int {
        switch forType {
        case bool:      return 1
        case enum32:    return 4
        case int32:     return 4
        case uint32:    return 4
        case int64:     return 8
        case uint64:    return 8
        case double:    return 8
        case uuid:      return 16
        case date:      return 8
        case oobdata:   return 8
            
        default:
            return 0
        }
    }
}



public class SpecField: SpecItem {
    public var type: SpecType!
    public var required: Bool = false
    
    public override init(name: String, spec: P7Spec, attributes: [String : Any]) {
        super.init(name: name, spec: spec, attributes: attributes)
        
        if let typeName = attributes["type"] as? String {
            self.type = SpecType.specType(forString: typeName)
        }
    }
    
    public func hasExplicitLength() -> Bool {
        return type == .string || type == .data || type == .list
    }
}



public class SpecMessage: SpecItem {
    public var parameters : [SpecField] = []
    
    public override init(name: String, spec: P7Spec, attributes: [String : Any]) {
        super.init(name: name, spec: spec, attributes: attributes)
    }
}



public class SpecError: SpecItem {
    
}




/**
 This class is a wrapper for the Wired 2.0 specification.
 The specification is based on a XML file named "wired.xml"
 that defines types, fields, messages, transactions and many
 other data-structures that are used by the Wired protocol.
 The Spec class is mainly used to construct, handle
 and verify messages against the specification. It defines
 a set of classes and methods that abstract and optimize
 operations around the XML specification.
 
 The Spec class also takes care of the built-in XSD specification
 internally used by the protocol to establish communication.
 
     // Initialize a specification based on a XML file
     spec = Spec(withPath: "wired.xml")
 
 @author Rafaël Warnault (mailto:dev@read-write.fr)
 */
public class P7Spec: NSObject, XMLParserDelegate {
    private var parser = XMLParser()
    
    public var xml: String?
    
    public var builtinProtocolVersion: String?
    public var protocolVersion: String?
    public var protocolName:    String?
    
    public var fields:          [SpecField]             = []
    public var fieldsByName:    [String:SpecField]      = [:]
    public var fieldsByID:      [Int:SpecField]         = [:]
    
    public var messages:        [SpecMessage]           = []
    public var messagesByName:  [String:SpecMessage]    = [:]
    public var messagesByID:    [Int:SpecMessage]       = [:]
    
    public var errors:          [SpecError]             = []
    public var errorsByID:      [Int:SpecError]         = [:]
    
    private var currentMessage: SpecMessage?
    
    public var path: String?

    /**
     The following XML long string contains the built-in XSD
     specification against which the Wired protocol is built.
     
     This part of the specification is responsible of the connection
     handshake, setup of encryption, compression settings, and compatibility
     check between peers.
     
     This scheame is automatically loaded alongside the hosted
     specification loaded at `init()`
     */
    public var p7xml: String = """
<?xml version="1.0" encoding="UTF-8"?>
<p7:protocol xmlns:p7="http://wired.read-write.fr/P7/Specification"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://wired.read-write.fr/wired/html/p7-specification.xsd"
       name="P7"
       version="1.0">

  <p7:types>
    <p7:type name="bool" id="1" size="1" />
    <p7:type name="enum" id="2" size="4" />
    <p7:type name="int32" id="3" size="4" />
    <p7:type name="uint32" id="4" size="4" />
    <p7:type name="int64" id="5" size="8" />
    <p7:type name="uint64" id="6" size="8" />
    <p7:type name="double" id="7" size="8" />
    <p7:type name="string" id="8" />
    <p7:type name="uuid" id="9" size="16" />
    <p7:type name="date" id="10" size="8" />
    <p7:type name="data" id="11" />
    <p7:type name="oobdata" id="12" size="8" />
    <p7:type name="list" id="13" />
  </p7:types>

  <p7:fields>
    <p7:field name="p7.handshake.version" type="string" id="1" />
    <p7:field name="p7.handshake.protocol.name" type="string" id="2" />
    <p7:field name="p7.handshake.protocol.version" type="string" id="3" />
    <p7:field name="p7.handshake.compression" type="enum" id="4">
      <p7:enum name="p7.handshake.compression.deflate" value="0" />
    </p7:field>
    <p7:field name="p7.handshake.encryption" type="enum" id="5">
      <p7:enum name="p7.handshake.encryption.rsa_aes128_sha1" value="0" />
      <p7:enum name="p7.handshake.encryption.rsa_aes192_sha1" value="1" />
      <p7:enum name="p7.handshake.encryption.rsa_aes256_sha1" value="2" />
      <p7:enum name="p7.handshake.encryption.rsa_bf128_sha1" value="3" />
      <p7:enum name="p7.handshake.encryption.rsa_3des192_sha1" value="4" />
    </p7:field>
    <p7:field name="p7.handshake.checksum" type="enum" id="6">
      <p7:enum name="p7.handshake.checksum.sha1" value="0" />
    </p7:field>
    <p7:field name="p7.handshake.compatibility_check" type="bool" id="7" />

    <p7:field name="p7.encryption.public_key" id="9" type="data" />
    <p7:field name="p7.encryption.cipher.key" id="10" type="data" />
    <p7:field name="p7.encryption.cipher.iv" id="11" type="data" />
    <p7:field name="p7.encryption.username" id="12" type="data" />
    <p7:field name="p7.encryption.client_password" id="13" type="data" />
    <p7:field name="p7.encryption.server_password" id="14" type="data" />

    <p7:field name="p7.compatibility_check.specification" id="15" type="string" />
    <p7:field name="p7.compatibility_check.status" id="16" type="bool" />
  </p7:fields>

  <p7:messages>
    <p7:message name="p7.handshake.client_handshake" id="1">
      <p7:parameter field="p7.handshake.version" use="required" />
      <p7:parameter field="p7.handshake.protocol.name" use="required" />
      <p7:parameter field="p7.handshake.protocol.version" use="required" />
      <p7:parameter field="p7.handshake.encryption" />
      <p7:parameter field="p7.handshake.compression" />
      <p7:parameter field="p7.handshake.checksum" />
    </p7:message>

    <p7:message name="p7.handshake.server_handshake" id="2">
      <p7:parameter field="p7.handshake.version" use="required" />
      <p7:parameter field="p7.handshake.protocol.name" use="required" />
      <p7:parameter field="p7.handshake.protocol.version" use="required" />
      <p7:parameter field="p7.handshake.encryption" />
      <p7:parameter field="p7.handshake.compression" />
      <p7:parameter field="p7.handshake.checksum" />
      <p7:parameter field="p7.handshake.compatibility_check" />
    </p7:message>

    <p7:message name="p7.handshake.acknowledge" id="3">
      <p7:parameter field="p7.handshake.compatibility_check" />
    </p7:message>

    <p7:message name="p7.encryption.server_key" id="4">
      <p7:parameter field="p7.encryption.public_key" use="required" />
    </p7:message>

    <p7:message name="p7.encryption.client_key" id="5">
      <p7:parameter field="p7.encryption.cipher.key" use="required" />
      <p7:parameter field="p7.encryption.cipher.iv" />
      <p7:parameter field="p7.encryption.username" use="required" />
      <p7:parameter field="p7.encryption.client_password" use="required" />
    </p7:message>

    <p7:message name="p7.encryption.acknowledge" id="6">
      <p7:parameter field="p7.encryption.server_password" use="required" />
    </p7:message>

    <p7:message name="p7.encryption.authentication_error" id="7" />

    <p7:message name="p7.compatibility_check.specification" id="8">
      <p7:parameter field="p7.compatibility_check.specification" use="required" />
    </p7:message>
    
    <p7:message name="p7.compatibility_check.status" id="9">
      <p7:parameter field="p7.compatibility_check.status" use="required" />
    </p7:message>
  </p7:messages>

  <p7:transactions>
    <p7:transaction message="p7.handshake.client_handshake" originator="client" use="required">
      <p7:reply message="p7.handshake.server_handshake" count="1" use="required" />
    </p7:transaction>

    <p7:transaction message="p7.handshake.server_handshake" originator="server" use="required">
      <p7:reply message="p7.handshake.acknowledge" count="1" use="required" />
    </p7:transaction>

    <p7:transaction message="p7.encryption.server_key" originator="server" use="required">
      <p7:reply message="p7.encryption.client_key" count="1" use="required" />
    </p7:transaction>

    <p7:transaction message="p7.encryption.client_key" originator="client" use="required">
      <p7:or>
        <p7:reply message="p7.encryption.acknowledge" count="1" use="required" />
        <p7:reply message="p7.encryption.authentication_error" count="1" use="required" />
      </p7:or>
    </p7:transaction>

    <p7:transaction message="p7.compatibility_check.specification" originator="both" use="required">
      <p7:reply message="p7.compatibility_check.status" count="1" use="required" />
    </p7:transaction>
  </p7:transactions>
</p7:protocol>
"""
    
    
    /**
     Init a new specification object for a given XML
     specification file.

    - Parameters:
        - path: The path of your XML specification file

    - Returns: An instance of P7Spec
    */
    public init(withPath path: String? = nil) {
        super.init()
        
        let data = p7xml.data(using: .utf8)
        self.parser = XMLParser(data: data!)
        self.parser.delegate = self
        
        self.parser.parse()
        
        do {
            let builtinDoc = try AEXMLDocument(xml: p7xml)
            self.builtinProtocolVersion = builtinDoc.root.attributes["version"]

        } catch {
            Logger.error("ERROR: Cannot parse built-in spec, fatal")
        }
        
        if let p = path {
            self.loadFile(path: p)
        } else {
            if let p = Bundle(identifier: "fr.read-write.WiredSwift")!.path(forResource: "wired", ofType: "xml") {
                self.loadFile(path: p)
            }
        }
    }
    
    
    /**
    Check whether the given specification name and version
     are compatible with the current protocol.

    - Parameters:
        - name: The name of your spec (here, Wired)
        - version: The version of the given spec

    - Returns: A boolean set to `true` if compatible
    */
    public func isCompatibleWithProtocol(withName name:String, version: String) -> Bool {
        // TODO: check compatibility
        return true
    }
    
    
    /**
     Returns an error for a given P7 Message

    - Parameters:
        - message: The error message

    - Returns: An instance of SpecError
    */
    public func error(forMessage message: P7Message) -> SpecError?{
        if let errorID = message.enumeration(forField: "wired.error") {
            return errorsByID[Int(errorID)]
        }
        return nil
    }
    

    
    /**
     XMLParser parser method
    */
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "p7:field" {
            self.loadField(attributeDict)
        }
        else if elementName == "p7:message" {
            self.loadMessage(attributeDict)
        }
        else if elementName == "p7:parameter" {
            self.loadParam(attributeDict)
        }
        else if elementName == "p7:enum" {
            if let name = attributeDict["name"] {
                if name.starts(with: "wired.error.") {
                    self.loadError(attributeDict)
                }
            }
        }
    }
    
    
    
    private func loadError(_ attributes: [String : String]) {
        guard let name = attributes["name"] else {
            return
        }
        
        guard let value = attributes["value"], let asInt = Int(value) else {
            return
        }
        
        let e = SpecError(name: name, spec: self, attributes: attributes)
        errors.append(e)
        errorsByID[asInt] = e
    }
    
    
    private func loadFile(path: String) {        
        let url = URL(fileURLWithPath: path)
        
        self.xml = try? String(contentsOf: url, encoding: .utf8)
        
        self.parser = XMLParser(contentsOf: url)!
        
        self.parser.delegate = self
        self.parser.parse()
    }

    
    
    private func loadField(_ attributes: [String : String]) {
        guard let name = attributes["name"] else {
            return
        }
        
        guard let strID = attributes["id"], let fieldID = Int(strID) else {
            return
        }
        
        let field = SpecField(name: name, spec: self, attributes: attributes)
        self.fields.append(field)
        self.fieldsByName[name]     = field
        self.fieldsByID[fieldID]    = field
    }
    
    
    private func loadMessage(_ attributes: [String : String]) {
        guard let name = attributes["name"] else {
            return
        }
        
        guard let strID = attributes["id"], let messageID = Int(strID) else {
            return
        }
        
        let message = SpecMessage(name: name, spec: self, attributes: attributes)
        self.messages.append(message)
        
        self.messagesByName[name]       = message
        self.messagesByID[messageID]    = message
        
        self.currentMessage = message
    }
    
    
    private func loadParam(_ attributes: [String : String]) {
        guard let fieldName = attributes["field"] else {
            return
        }
        
        if let cm = self.currentMessage, let field = self.fieldsByName[fieldName] {
            cm.parameters.append(field)
        }
    }

    
    private func loadTransaction() {
        
    }
}
