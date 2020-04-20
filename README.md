# WiredSwift

WiredSwift is an implementation of the Wired 2.0 protocol written in Swift. 

[![Actions Status](https://github.com/nark/WiredSwift/workflows/Swift/badge.svg)](https://github.com/nark/WiredSwift/actions)


## Requirements

* macOS 10.14
* iOS 12
* Xcode 

## Dependencies

Dependencies are managed by Swift Package Manager, have a look to the [Package.swif](https://github.com/nark/WiredSwift/blob/master/Package.swift) file for details. 

## Getting Started

### Adding to your project

Latest release version:

    .package(name: "WiredSwift", url: "https://github.com/nark/WiredSwift", from: "1.0.6")

Latest upstream version:

    .package(name: "WiredSwift", url: "https://github.com/nark/WiredSwift", .branch("master"))
    
### Connection

Minimal connection to a Wired 2.0 server:

    let specUrl = URL(string: "https://wired.read-write.fr/spec.xml")!
    let spec = P7Spec(withUrl: specUrl)

    // the Wired URL to connect to
    let url = Url(withString: "wired://localhost:4871")

    // init connection
    let connection = Connection(withSpec: spec, delegate: self)
    connection.nick = "Me"
    connection.status = "Testing WiredSwift"

    // perform  connect
    if connection.connect(withUrl: url) {
        // connected
    } else {
        // not connected
        print(connection.socket.errors)
    }

### Join to the public chat

Once connected, in order to login into the public chat and list connected users, you have to explicitely trigger the `wired.chat.join_chat` transaction. The `Connection` class can help you by calling the following method:

    connection.joinChat(chatID: 1)
    
Where `1` is always the ID of the public chat regarding the Wired 2.0 protocol.

### Receive messages

While using interactive mode, you have to comply with the `ConnectionDelegate` protocol to receive messages (`P7Message`) or any other events from the initiated connection. For example, the `connectionDidSendMessage(connection: Connection, message: P7Message)` method will distribute received messages which you can handle as the following:

    extension Controller: ConnectionDelegate {
        func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
            if  message.name == "wired.chat.user_list" {
                print(message.xml())
            }
        }
        
        func connectionDidReceiveError(connection: Connection, message: P7Message) {
            if let specError = spec.error(forMessage: message), let errorMessage = specError.name {
                print(errorMessage)
            }
        }
    }
    
### Send messages

The following example illustrate how to send a message:

    let message = P7Message(withName: "wired.chat.say", spec: spec)
    message!.addParameter(field: "wired.chat.id", value: 1) // public chat ID
    message!.addParameter(field: "wired.chat.say", value: "Hello, world!")
    
    self.connection.send(message: message!)
    
To learn more about the Wired 2.0 specification you can visit this documentation: [http://wired.read-write.fr/spec.html](http://wired.read-write.fr/spec.html) and read the orginal code of the `libwired` C library: [https://github.com/nark/libwired](https://github.com/nark/libwired)

### Interactive socket

The `Connection` class provides two ways of handling messages:

* connection instance is set as `interactive` so it will automatically manage a listening loop in a separated thread and dispatch receive message through `ConnectionDelegate` protocol to registered delegates in the main thread. This is the default behavior.
* connection instance is NOT `interactive`, and in that case you have to handle every message read/write transactions by yourself using `Connection.readMessage()` and `Connection.sendMessage()` methods. This for example is used for transfers separated connections that have different behaviors.

Set the `interactive` attribute to `false` before calling `Connection.connect()` if you want to use uninteractive mode.

### Client Info Delegate

The `Connection` class provides the `ClientInfoDelegate` to return custom values for `wired.info.application.name`, `wired.info.application.version` and `wired.info.application.build` of the `wired.client_info` message. 

    extension Controller: ClientInfoDelegate {
        func clientInfoApplicationName(for connection: Connection) -> String? {
            return "My Swift Client"
        }

        func clientInfoApplicationVersion(for connection: Connection) -> String? {
            return "1.0"
        }

        func clientInfoApplicationBuild(for connection: Connection) -> String? {
            return "99"
        }
    }
    
### Logger

You can configure the `Logger` class of WiredSwift as follow:

    // set the max vele severity
    Logger.setMaxLevel(.ERROR)
    
    // completely remove STDOUT console output
    Logger.removeDestination(.Stdout)

## Development

### Build

    swift build -v
    
### Run Tests
    
    swift test -v
    
### Xcode project

You can (re)genrerate Xcode project by using:

    swift package generate-xcodeproj
    
## Contribute

You are welcome to contribute using issues and pull-requests if you want to.

Focus is on:

* socket IO stability: the quality of in/out data interpretation and management through the Wired socket
* mutli-threading stability: the ability to interact smoothly between connections and UIs
* low-level unit tests: provides a strong implementation to enforce the integrity of the specification
* specification compliance: any not yet implemented features that require kilometers of code…
* limit regression from the original implementation

Check the GitHub « Projects » page to get a sneap peek on the project insights and progress:  https://github.com/nark/WiredSwift/projects

## License

This code is distributed under BSD license, and it is free for personal or commercial use.
        
- Copyright (c) 2003-2009 Axel Andersson, All rights reserved.
- Copyright (c) 2011-2020 Rafaël Warnault, All rights reserved.
        
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
        
Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
        
THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
