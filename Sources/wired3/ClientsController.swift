//
//  ClientsController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/04/2021.
//

import Foundation
import WiredSwift

public class ClientsController {
    var connectedClients: [UInt32: Client] = [:]
    var clientsLock: Lock = Lock()

    public func user(withID userID: UInt32) -> Client? {
        self.clientsLock.concurrentlyRead {
            self.connectedClients[userID]
        }
    }

    public func addClient(client: Client) {
        self.clientsLock.exclusivelyWrite {
            self.connectedClients[client.userID] = client
        }
        // Logger must NOT be called inside the write-lock: loggerDidLog →
        // broadcastEntry → connectedClientsSnapshot() would try to re-acquire
        // the same lock on the same thread, causing a deadlock.
        WiredSwift.Logger.debug("Client \(client.userID) added — connected: \(self.connectedClientsSnapshot().count)")
    }

    public func removeClient(client: Client) {
        client.socket.disconnect()

        self.clientsLock.exclusivelyWrite {
            self.connectedClients[client.userID] = nil
        }
        // Same re-entrancy risk as addClient — keep Logger calls outside the lock.
        WiredSwift.Logger.debug("Client \(client.userID) removed — connected: \(self.connectedClientsSnapshot().count)")
    }

    public func broadcast(message: P7Message) {
        DispatchQueue.global(qos: .default).async {
            self.clientsLock.concurrentlyRead {
                for (_, client) in self.connectedClients {
                    _ = App.serverController.send(message: message, client: client)
                }
            }
        }
    }

    public func connectedClientsSnapshot() -> [Client] {
        self.clientsLock.concurrentlyRead {
            Array(self.connectedClients.values)
        }
    }
}
