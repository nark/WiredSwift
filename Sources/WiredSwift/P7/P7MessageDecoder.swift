//
//  P7MessageDecoder.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 13/05/2021.
//

import Foundation
import NIO

public struct P7MessageDecoder: ByteToMessageDecoder {
    public typealias InboundOut = ByteBuffer
    private var socket:P7Socket!
    private var messageLength:UInt32!
    
    public init(withSocket socket: P7Socket) {
        self.socket = socket
    }

    public mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) -> DecodingState {
        if self.messageLength == nil {
            guard let length = buffer.readInteger(endianness: .big, as: UInt32.self) else {
                return .needMoreData
            }
            
             self.messageLength = length
        }
                
        guard var payload = buffer.readSlice(length: Int(self.messageLength)) else {
            return .needMoreData
        }
                        
        if self.socket.checksumEnabled {
            guard let remoteChecksum = buffer.readData(length: self.socket.checksumLength) else {
                return .needMoreData
            }
            
            payload.writeData(remoteChecksum)
        }
        
        self.messageLength = nil
        
        context.fireChannelRead(self.wrapInboundOut(payload))
        
        return .continue
    }
}
