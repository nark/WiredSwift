import Foundation
import WiredSwift

extension ServerController {
    func receiveTrackerGetCategories(client: Client, message: P7Message) {
        guard let user = client.user else { return }
        guard trackerEnabled else {
            replyError(client: client, error: "wired.error.tracker_not_enabled", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.tracker.list_servers") else {
            replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        App.trackerController.replyCategories(to: client, message: message, categories: trackerCategories, spec: self.spec)
        recordEvent(.trackerGotCategories, client: client)
    }

    func receiveTrackerGetServers(client: Client, message: P7Message) {
        guard let user = client.user else { return }
        guard trackerEnabled else {
            replyError(client: client, error: "wired.error.tracker_not_enabled", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.tracker.list_servers") else {
            replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        App.trackerController.replyServerList(to: client, message: message, spec: self.spec)
        recordEvent(.trackerGotServers, client: client)
    }

    func receiveTrackerSendRegister(client: Client, message: P7Message) {
        guard let user = client.user else { return }
        guard trackerEnabled else {
            replyError(client: client, error: "wired.error.tracker_not_enabled", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.tracker.register_servers") else {
            replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            let trackedServer = try App.trackerController.registerServer(
                client: client,
                message: message,
                allowedCategories: trackerCategories
            )
            replyOK(client: client, message: message)
            recordEvent(.trackerRegisteredServer, client: client, parameters: [trackedServer.name])
        } catch TrackerController.TrackerError.invalidMessage {
            replyError(client: client, error: "wired.error.invalid_message", message: message)
        } catch TrackerController.TrackerError.internalError {
            replyError(client: client, error: "wired.error.internal_error", message: message)
        } catch {
            replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    func receiveTrackerSendUpdate(client: Client, message: P7Message) {
        guard let user = client.user else { return }
        guard trackerEnabled else {
            replyError(client: client, error: "wired.error.tracker_not_enabled", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.tracker.register_servers") else {
            replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            _ = try App.trackerController.updateServer(client: client, message: message)
            replyOK(client: client, message: message)
        } catch TrackerController.TrackerError.invalidMessage {
            replyError(client: client, error: "wired.error.invalid_message", message: message)
        } catch TrackerController.TrackerError.notRegistered {
            replyError(client: client, error: "wired.error.not_registered", message: message)
        } catch TrackerController.TrackerError.internalError {
            replyError(client: client, error: "wired.error.internal_error", message: message)
        } catch {
            replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }
}
