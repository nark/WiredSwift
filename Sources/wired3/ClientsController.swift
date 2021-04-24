//
//  ClientsController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/04/2021.
//

import Foundation
import WiredSwift

public class ClientsController {
    var connectedClients:[UInt32:Client] = [:]
    
    
    public func addClient(client: Client) {
        self.connectedClients[client.userID] = client

        WiredSwift.Logger.info("Connected clients: \(self.connectedClients)")
    }
    

    
    public func removeClient(client: Client) {
        client.socket.disconnect()
        
        self.connectedClients[client.userID] = nil
        
        WiredSwift.Logger.info("Connected users: \(self.connectedClients)")
    }
    
    
    
    public func broadcast(message:P7Message) {
        DispatchQueue.global(qos: .default).async {
            for (_, client) in self.connectedClients {
                _ = App.serverController.send(message: message, client: client)
            }
        }
    }
}
