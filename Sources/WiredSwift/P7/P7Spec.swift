//
//  Spec.swift
//  Wired
//
//  Created by Rafael Warnault on 17/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import AEXML



public typealias SpecItem           = P7SpecItem
public typealias SpecType           = P7SpecType
public typealias SpecField          = P7SpecField
public typealias SpecMessage        = P7SpecMessage
public typealias SpecTransaction    = P7SpecTransaction
public typealias SpecError          = P7SpecError





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
 
 @author Rafaël Warnault (mailto:rw@read-write.fr)
 */
public class P7Spec: NSObject, XMLParserDelegate {
    private var parser:XMLParser = XMLParser(data: Data())
    
    public var xml: String?
    
    public var builtinProtocolVersion: String?
    public var protocolVersion: String?
    public var protocolName:    String?
    
    public var fields:          [SpecField]             = []
    public var fieldsByName:    [String:SpecField]      = [:]
    public var fieldsByID:      [UInt32:SpecField]         = [:]
    
    public var messages:        [SpecMessage]           = []
    public var messagesByName:  [String:SpecMessage]    = [:]
    public var messagesByID:    [Int:SpecMessage]       = [:]
    
    public var transactionsByName: [String:SpecTransaction]    = [:]
    
    private var accountPrivilegesLock:Bool = false
    public var accountPrivileges:[String]? = nil
    
    public var errors:          [SpecError]             = []
    public var errorsByID:      [Int:SpecError]         = [:]
    public var errorsByName:    [String:SpecError]         = [:]
    
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
      <p7:enum name="p7.handshake.compression.deflate" value="2" />
    </p7:field>
    <p7:field name="p7.handshake.encryption" type="enum" id="5">
        <p7:enum name="p7.handshake.encryption.ecdh_aes256_sha256" value="2" />
        <p7:enum name="p7.handshake.encryption.ecdh_chacha20_sha256" value="3" />
    </p7:field>
    <p7:field name="p7.handshake.checksum" type="enum" id="6">
      <p7:enum name="p7.handshake.checksum.sha2_256" value="2" />
      <p7:enum name="p7.handshake.checksum.sha3_256" value="3" />
      <p7:enum name="p7.handshake.checksum.hmac_256" value="4" />
      <p7:enum name="p7.handshake.checksum.poly_1305" value="5" />
    </p7:field>
    <p7:field name="p7.handshake.compatibility_check" type="bool" id="7" />

    <p7:field name="p7.encryption.public_key" id="9" type="data" />
    <p7:field name="p7.encryption.cipher.key" id="10" type="data" />
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
    Init the built-in spec
    */
    
    private override init() {
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
    }
    
    
    
    /**
     Init a new specification object for a given XML
     specification file.

    - Parameters:
        - path: The path of your XML specification file

    - Returns: An instance of P7Spec
    */
    public convenience init(withPath path: String? = nil) {
        self.init()
        
        if let p = path {
            self.loadFile(path: p)
        } else {
            if let p = Bundle(identifier: "fr.read-write.WiredSwift")!.path(forResource: "wired", ofType: "xml") {
                self.loadFile(path: p)
            }
        }
    }
    
    /**
     Init a new specification object for a given XML
     specification file.

    - Parameters:
        - url: The URL of your XML specification file

    - Returns: An instance of P7Spec
    */
    public convenience init?(withUrl url:URL) {
        self.init()
        
        if !self.loadFile(at: url) {
            return nil
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
        if name != self.protocolName {
            return false
        }
        
        if version != self.protocolVersion {
            return false
        }
        
        return true
    }
    
    
    /**
     Returns an error for a given P7 Message

    - Parameters:
        - message: The error message

    - Returns: An instance of SpecError
    */
    public func error(forMessage message: P7Message) -> SpecError? {
        if let errorID = message.enumeration(forField: "wired.error") {
            return errorsByID[Int(errorID)]
        }
        return nil
    }
    
    public func error(withName: String) -> SpecError? {
        return errorsByName[withName]
    }
    

    
    /**
     XMLParser parser method
    */
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "p7:protocol" {
            if let name = attributeDict["name"] {
                self.protocolName = name
            }
            if let version = attributeDict["version"] {
                self.protocolVersion = version
            }
        }
        else if elementName == "p7:field" {
            self.loadField(attributeDict)
        }
        else if elementName == "p7:message" {
            self.loadMessage(attributeDict)
        }
        else if elementName == "p7:collection" {
            if attributeDict["name"] == "wired.account.privileges" {
                accountPrivileges = []
                accountPrivilegesLock = true
            }
        }
        else if elementName == "p7:member" {
            if accountPrivilegesLock {
                accountPrivileges?.append(attributeDict["field"]!)
            }
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
    
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "p7:collection" {
            if accountPrivilegesLock {
                accountPrivilegesLock = false
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
        e.id = value
        
        errors.append(e)
        errorsByID[asInt] = e
        errorsByName[name] = e
    }
    
    
    private func loadFile(path: String) {
        let url = URL(fileURLWithPath: path)
        
        self.loadFile(at: url)
    }
    
    
    @discardableResult
    private func loadFile(at url:URL) -> Bool {
        do {
            self.xml = try String(contentsOf: url, encoding: .utf8)
            
            self.parser = XMLParser(contentsOf: url)!
            self.parser.delegate = self
            self.parser.parse()
            
            Logger.debug("Loaded spec \(self.protocolName!) version \(self.protocolVersion!)")
            
        } catch let e {
            Logger.error("Cannot load spec at URL: \(e.localizedDescription)")
            return false
        }
        return true
    }

    
    
    private func loadField(_ attributes: [String : String]) {
        guard let name = attributes["name"] else {
            return
        }
        
        guard let strID = attributes["id"], let fieldID = UInt32(strID) else {
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
