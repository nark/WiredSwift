//
//  Message.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//
// swiftlint:disable cyclomatic_complexity
// TODO: Replace large switch in P7Message serialization with a dispatch table

import Foundation
import AEXML

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
    public var size: Int = 0

    private var parameters: [String: Any] = [String: Any](minimumCapacity: 50)

    public var numberOfParameters: Int {
        self.parameters.count
    }
    public var parameterKeys: [String] {
        Array(self.parameters.keys)
    }

    public override var description: String { self.xml() }

    public init(withName name: String, spec: P7Spec) {
        if let specMessage = spec.messagesByName[name] {
            self.specMessage    = specMessage
            self.id             = specMessage.attributes["id"] as? String
            self.name           = name
            self.spec           = spec
        } else {
            // SECURITY (FINDING_P_009): Log warning when message name not found in spec
            Logger.error("WARNING: Message name '\(name)' not found in spec — message will have nil properties")
            self.name = name
            self.spec = spec
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
        } else if spec.fieldsByName[field]?.type == .int32 ||
                spec.fieldsByName[field]?.type == .uint32 {
            if let val = value as? UInt32 {
                return String(val)
            }
        } else if spec.fieldsByName[field]?.type == .int64 ||
                spec.fieldsByName[field]?.type == .uint64 {
            if let val = value as? UInt64 {
                return String(val)
            }
        } else if spec.fieldsByName[field]?.type == .enum32 {
            if value is UInt32 {
                // print("field")
            }
        } else if spec.fieldsByName[field]?.type == .data {
            if let val = value as? Data {
                return val.toHex()
            }
        } else if spec.fieldsByName[field]?.type == .oobdata {
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

    public func list(forField field: String) -> [Any]? {
        if let list = self.parameters[field] as? [Any] {
            return list
        }
        return nil
    }

    public func stringList(forField field: String) -> [String]? {
        if let list = self.parameters[field] as? [String] {
            return list
        }
        return nil
    }

    public func date(forField field: String) -> Date? {
        if let value = self.parameters[field] as? Date {
            return value
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
        if let value = self.parameters[field] as? UInt64 {
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

    public func xml() -> String {
        let message = AEXMLDocument()
        let root = message.addChild(name: "p7:message", attributes: ["name": self.name] )

        for (field, value) in self.parameters {
            let p = root.addChild(name: "p7:field", attributes: ["name": field])

            if  spec.fieldsByName[field]?.type == .string ||
                spec.fieldsByName[field]?.type == .uuid {
                if let string = value as? String {
                    p.value = string
                }
            } else if spec.fieldsByName[field]?.type == .int32 ||
                    spec.fieldsByName[field]?.type == .uint32 {
                if let val = value as? UInt32 {
                    p.value = String(val)
                }
            } else if spec.fieldsByName[field]?.type == .bool {
                if let val = value as? UInt32 {
                    p.value = val == 1 ? "true" : "false"
                }
            } else if spec.fieldsByName[field]?.type == .int64 ||
                    spec.fieldsByName[field]?.type == .uint64 {
                if let val = value as? UInt64 {
                    p.value = String(val)
                }
            } else if spec.fieldsByName[field]?.type == .data ||
                    spec.fieldsByName[field]?.type == .oobdata {
                if let val = value as? Data {
                    p.value = val.toHex()
                }
            } else if spec.fieldsByName[field]?.type == .date {
                if let val = value as? Double {
                    let dateFormatter = ISO8601DateFormatter()
                    p.value = dateFormatter.string(from: Date(timeIntervalSince1970: val))
                }
            } else if spec.fieldsByName[field]?.type == .list {
                if let val = value as? [String] {
                    p.value = val.joined(separator: ",")
                }
            }
            // TODO: complete all types
        }

        return "\(message.xml)"
    }

    public func bin() -> Data {
        var data = Data()

        // append message ID
        if let messageID = UInt32(self.id) {
            data.append(uint32: messageID, bigEndian: true)

            // append fields
            for (field, value) in self.parameters {
                if let specField = spec.fieldsByName[field] {
                    // print("specField \(specField.name)")
                    if let fieldIDStr = specField.id {
                        // append field ID
                        if let fieldID = UInt32(fieldIDStr) {
                            data.append(uint32: fieldID, bigEndian: true)

                            // append value
                            if specField.type == .bool { // boolean (1)
                                let v = (value as? Bool) == true ? UInt8(1) : UInt8(0)
                                data.append(uint8: v, bigEndian: true)

                            } else if specField.type == .enum32 { // enum (4)
                                data.append(uint32: self.coerceUInt32(value), bigEndian: true)

                            } else if specField.type == .int32 { // int32 (4)
                                data.append(uint32: self.coerceUInt32(value), bigEndian: true)

                            } else if specField.type == .uint32 { // uint32 (4)
                                data.append(uint32: self.coerceUInt32(value), bigEndian: true)

                            } else if specField.type == .int64 { // int64 (4)
                                data.append(uint64: self.coerceUInt64(value), bigEndian: true)

                            } else if specField.type == .uint64 { // uint64 (4)
                                data.append(uint64: self.coerceUInt64(value), bigEndian: true)

                            } else if specField.type == .double { // double (4)
                                if let doubleValue = value as? Double {
                                    data.append(double: doubleValue, bigEndian: true)
                                } else {
                                    Logger.error("WARNING: Expected Double for field '\(field)', skipping")
                                }

                            } else if specField.type == .string { // string (x)
                                if let str = value as? String {
                                    // if let d = str.nullTerminated {
                                        let l = UInt32(str.bytes.count)
                                        data.append(uint32: l, bigEndian: true)
                                        data.append(Data(str.bytes))
                                    // }
                                }
                            } else if specField.type == .uuid { // uuid (16)
                                if let str = value as? String,
                                   let uuid = UUID(uuidString: str) {
                                    var uuidValue = uuid.uuid
                                    withUnsafeBytes(of: &uuidValue) { rawBytes in
                                        data.append(rawBytes.bindMemory(to: UInt8.self))
                                    }
                                }
                            } else if specField.type == .date { // date (8)
                                if let date = value as? Date {
                                    data.append(Data(from: date.timeIntervalSince1970))
                                }
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
                                if let list = value as? [String] {
                                    var listData = Data()
                                    for string in list {
                                        let bytes = Array(string.utf8) + [0]
                                        listData.append(uint32: UInt32(bytes.count), bigEndian: true)
                                        listData.append(Data(bytes))
                                    }
                                    data.append(uint32: UInt32(listData.count), bigEndian: true)
                                    data.append(listData)
                                } else if let list = value as? [Any] {
                                    var listData = Data()
                                    for item in list {
                                        guard let string = item as? String else { continue }
                                        let bytes = Array(string.utf8) + [0]
                                        listData.append(uint32: UInt32(bytes.count), bigEndian: true)
                                        listData.append(Data(bytes))
                                    }
                                    data.append(uint32: UInt32(listData.count), bigEndian: true)
                                    data.append(listData)
                                } else {
                                    data.append(uint32: 0, bigEndian: true)
                                }
                            }
                        }
                    }
                }
            }
        }

        self.size = data.count

        return data
    }

    private func coerceUInt32(_ any: Any) -> UInt32 {
        if let value = any as? UInt32 {
            return value
        }
        if let value = any as? Int {
            return UInt32(clamping: value)
        }
        if let value = any as? Int64 {
            return UInt32(clamping: value)
        }
        if let value = any as? UInt64 {
            return UInt32(clamping: value)
        }
        if let value = any as? UInt8 {
            return UInt32(value)
        }
        if let value = any as? Bool {
            return value ? 1 : 0
        }
        if let value = any as? NSNumber {
            return value.uint32Value
        }
        if let value = any as? String, let parsed = UInt32(value) {
            return parsed
        }
        return 0
    }

    private func coerceUInt64(_ any: Any) -> UInt64 {
        if let value = any as? UInt64 {
            return value
        }
        if let value = any as? Int {
            return UInt64(clamping: value)
        }
        if let value = any as? Int64 {
            return UInt64(clamping: value)
        }
        if let value = any as? UInt32 {
            return UInt64(value)
        }
        if let value = any as? UInt8 {
            return UInt64(value)
        }
        if let value = any as? Bool {
            return value ? 1 : 0
        }
        if let value = any as? NSNumber {
            return value.uint64Value
        }
        if let value = any as? String, let parsed = UInt64(value) {
            return parsed
        }
        return 0
    }

    private func loadXMLMessage(_ xml: String) {
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

    /// Maximum size for a single TLV field value (16 MB).
    private static let maxFieldSize: Int = 16 * 1024 * 1024

    private func loadBinaryMessage(_ data: Data) {
        var offset = 0

        // SECURITY: bounds check before reading message ID
        guard data.count >= 4 else {
            Logger.error("ERROR : Message too short to contain message ID")
            return
        }

        let messageIDData = data.subdata(in: 0..<4)

        offset += 4

        if let v = messageIDData.uint32 {
            self.id = String(v)
        } else {
            Logger.error("ERROR : Cannot read message ID")
            return
        }

        guard let messageIDValue = messageIDData.uint32 else {
            Logger.error("ERROR : Cannot read message ID for spec lookup")
            return
        }

        if let specMessage = spec.messagesByID[Int(messageIDValue)] {
            self.name = specMessage.name!
            self.specMessage = specMessage

            var fieldIDData: Data!
            var fieldID: UInt32!

            while offset < data.count {
                // SECURITY: bounds check before reading field ID (4 bytes)
                guard offset + 4 <= data.count else {
                    Logger.error("ERROR : Truncated message — not enough data for field ID at offset \(offset)")
                    break
                }
                fieldIDData = data.subdata(in: offset..<offset+4)

                if let v = fieldIDData.uint32 {
                    fieldID = UInt32(v)
                } else {
                    Logger.error("ERROR : Cannot read field ID")
                    return
                }

                offset += 4

                if let specField = spec.fieldsByID[fieldID] {
                    var fieldLength = 0

                    // Logger.debug("READ field: \(specField.name) [\(fieldID)]")

                    // read length if needed
                    if specField.type == .string || specField.type == .data || specField.type == .list {
                        // SECURITY: bounds check before reading field length (4 bytes)
                        guard offset + 4 <= data.count else {
                            Logger.error("ERROR : Truncated message — not enough data for field length at offset \(offset)")
                            break
                        }
                        let fieldLengthData = data.subdata(in: offset..<offset+4)
                        guard let fieldLengthRaw = fieldLengthData.uint32 else {
                            Logger.error("ERROR : Cannot parse field length at offset \(offset)")
                            break
                        }
                        fieldLength = Int(fieldLengthRaw)
                        // SECURITY: reject oversized fields (FINDING_P_003)
                        guard fieldLength <= Self.maxFieldSize else {
                            Logger.error("ERROR : Field length \(fieldLength) exceeds maximum \(Self.maxFieldSize)")
                            break
                        }
                        offset += 4
                    } else {
                        fieldLength = SpecType.size(forType: specField.type)
                    }

                    if fieldLength == 0 && specField.type == .string {
                        // Keep explicit empty strings (length=0) instead of dropping the field.
                        self.addParameter(field: specField.name, value: "")
                    } else if fieldLength > 0 {
                        // SECURITY: bounds check before reading field data
                        guard offset + fieldLength <= data.count else {
                            Logger.error("ERROR : Truncated message — not enough data for field value at offset \(offset), need \(fieldLength) bytes, have \(data.count - offset)")
                            break
                        }
                        // read value
                        let fieldData = data.subdata(in: offset..<offset+fieldLength)

                        if specField.type == .bool {
                            self.addParameter(field: specField.name, value: fieldData.uint8.bigEndian)
                        } else if specField.type == .enum32 {
                            // Data.uint32 already converts BE→host via CFSwapInt32HostToBig.
                            // Applying .bigEndian again would double-swap, corrupting the value.
                            self.addParameter(field: specField.name, value: fieldData.uint32)
                        } else if specField.type == .int32 {
                            self.addParameter(field: specField.name, value: fieldData.uint32)
                        } else if specField.type == .uint32 {
                            self.addParameter(field: specField.name, value: fieldData.uint32)
                        } else if specField.type == .int64 {
                            self.addParameter(field: specField.name, value: fieldData.uint64)
                        } else if specField.type == .uint64 {
                            self.addParameter(field: specField.name, value: fieldData.uint64)
                        } else if specField.type == .double {
                            self.addParameter(field: specField.name, value: fieldData.double)
                        } else if specField.type == .string {
                            if let str = String(bytes: fieldData, encoding: .utf8) {
                                self.addParameter(field: specField.name, value: str)
                            } else {
                                Logger.error("WARNING: Invalid UTF-8 in field '\(specField.name)' — field rejected")
                            }
                        } else if specField.type == .uuid {
                            self.addParameter(field: specField.name, value: NSUUID(uuidBytes: Array(fieldData)).uuidString)
                        } else if specField.type == .date {
                            if let interval = fieldData.to(type: Double.self) {
                                self.addParameter(field: specField.name, value: Date(timeIntervalSince1970: interval))
                            }
                        } else if specField.type == .data {
                            self.addParameter(field: specField.name, value: fieldData)
                        } else if specField.type == .oobdata {
                            self.addParameter(field: specField.name, value: fieldData)
                        } else if specField.type == .list {
                            let listType = specField.attributes["listtype"] as? String
                            if listType == "string" {
                                var items: [String] = []
                                var listOffset = 0

                                while listOffset < fieldLength {
                                    guard listOffset + 4 <= fieldLength else { break }
                                    let sizeData = fieldData.subdata(in: listOffset..<(listOffset + 4))
                                    guard let itemSize = sizeData.uint32 else { break }
                                    let size = Int(itemSize)
                                    listOffset += 4

                                    guard size > 0 else { continue }
                                    guard listOffset + size <= fieldLength else { break }

                                    let itemData = fieldData.subdata(in: listOffset..<(listOffset + size))
                                    listOffset += size

                                    if size > 0 {
                                        let stringBytes = itemData.prefix(size - 1)
                                        if let string = String(bytes: stringBytes, encoding: .utf8) {
                                            items.append(string)
                                        }
                                    }
                                }

                                self.addParameter(field: specField.name, value: items)
                            }
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
            Logger.error("ERROR : Unknow message ID \(String(describing: self.id))")
            return
        }
    }
}
