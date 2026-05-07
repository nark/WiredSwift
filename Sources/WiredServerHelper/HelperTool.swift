import Foundation

final class HelperTool: NSObject, NSXPCListenerDelegate {

    let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: kHelperMachServiceName)
        super.init()
        listener.delegate = self
    }

    func run() {
        diagLog("listener.resume() calling…")
        listener.resume()
        diagLog("listener.resume() done — entering RunLoop.main.run()")
        RunLoop.main.run()
        diagLog("RunLoop.main.run() RETURNED — no input sources remain")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WiredHelperProtocol.self)
        connection.exportedObject = HelperDelegate()
        connection.resume()
        return true
    }
}
