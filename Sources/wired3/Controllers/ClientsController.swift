//
//  ClientsController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/04/2021.
//

import Foundation
import WiredSwift

/// Tracks all currently connected `Client` sessions by their session user ID.
///
/// All mutations are protected by a read-write lock so that the registry can
/// be read concurrently from multiple threads.
public class ClientsController {
    var connectedClients: [UInt32: Client] = [:]
    var clientsLock: Lock = Lock()

    /// Returns the connected client with the given session user ID, or `nil` if not connected.
    ///
    /// - Parameter userID: The session user ID assigned at login.
    /// - Returns: The matching `Client`, or `nil`.
    public func user(withID userID: UInt32) -> Client? {
        self.clientsLock.concurrentlyRead {
            self.connectedClients[userID]
        }
    }

    /// Registers a newly connected client in the session registry.
    ///
    /// - Parameter client: The client to register.
    public func addClient(client: Client) {
        self.clientsLock.exclusivelyWrite {
            self.connectedClients[client.userID] = client
        }
        // Logger must NOT be called inside the write-lock: loggerDidLog →
        // broadcastEntry → connectedClientsSnapshot() would try to re-acquire
        // the same lock on the same thread, causing a deadlock.
        WiredSwift.Logger.debug("Client \(client.userID) added — connected: \(self.connectedClientsSnapshot().count)")
    }

    /// Disconnects `client` and removes it from the session registry.
    ///
    /// - Parameter client: The client to remove.
    public func removeClient(client: Client) {
        client.socket.disconnect()

        self.clientsLock.exclusivelyWrite {
            self.connectedClients[client.userID] = nil
        }
        // Same re-entrancy risk as addClient — keep Logger calls outside the lock.
        WiredSwift.Logger.debug("Client \(client.userID) removed — connected: \(self.connectedClientsSnapshot().count)")
    }

    /// Sends `message` to every currently connected client asynchronously.
    ///
    /// Dispatched on a global default-priority queue to avoid blocking the caller.
    ///
    /// - Parameter message: The P7 message to broadcast.
    public func broadcast(message: P7Message) {
        DispatchQueue.global(qos: .default).async {
            self.clientsLock.concurrentlyRead {
                for (_, client) in self.connectedClients {
                    _ = App.serverController.send(message: message, client: client)
                }
            }
        }
    }

    /// Returns a point-in-time snapshot of all connected clients.
    ///
    /// Safe to iterate outside the lock because the returned array is a value copy.
    ///
    /// - Returns: An array of all currently connected `Client` instances.
    public func connectedClientsSnapshot() -> [Client] {
        self.clientsLock.concurrentlyRead {
            Array(self.connectedClients.values)
        }
    }

    /// Returns the login names of all currently connected authenticated clients.
    public func allConnectedLogins() -> [String] {
        self.clientsLock.concurrentlyRead {
            self.connectedClients.values.compactMap { $0.user?.username }
        }
    }

    /// Returns the connected client whose account login matches `login`, or `nil`.
    public func user(withLogin login: String) -> Client? {
        self.clientsLock.concurrentlyRead {
            self.connectedClients.values.first { $0.user?.username == login }
        }
    }
}
