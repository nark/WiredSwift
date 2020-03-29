# WiredSwift

WiredSwift is an implementation of the Wired 2.0 protocol written in Swift. 

## Requirements

* macOS 10.14
* Xcode 

## Dependencies

Init dependencies:

    cd WiredSwift
    carthage update

## Using WiredSwift

### Connection

Minimal connection to a Wired 2.0 server:

    // this automatically load P7 and Wired 2.0 specification
    let spec = P7Spec()
    
    // the Wired URL to connect to
    let url = Url(withString: "wired://guest@locahost:4871")
    
    // init connection
    let connection = Connection(withSpec: spec, delegate: self)
    connection.nick = "Me"
    connection.status = "Testing WiredSwift"
    
    // perform  connect
    if self.connection.connect(withUrl: url) {
        // connected
    } else {
        // not connected
        print(self.connection.socket.errors)
    }
    
### Interactive socket

The `Connection` class provides two ways of handling messages:

* connection instance is set as `interactive` so it will automatically manage a listening loop in a separated thread and dispatch receive message through `ConnectionDelegate` protocol to registered delegates in the main thread. This is the default behavior.
* connection instance is NOT `interactive`, and in that case you have to handle every message read/write transactions by yourself using `Connection.readMessage()` and `Connection.sendMessage()` methods. This for example used for transfers separated connections that have different iteractions.

Set the `interactive` attribute to `false` before calling `Connection.connect()` if you want to use uninteractive mode.

### Join to the public chat

Once connected, in order to login into the public chat and list connected users, you have to explicitely trigger the `wired.chat.join_chat` transaction. The `Connection` class can help you by calling the following method:

    connection.joinChat(chatID: 1)
    
Where `1` is always the ID of the public chat regarding the Wired 2.0 protocol.

### Receive messages

While using interactive mode, you have to comply with the `ConnectionDelegate` protocol to receive messages (`P7Message`) or any other events from the initiated connection. For example, the `connectionDidSendMessage(connection: Connection, message: P7Message)` method will distribute received messages which you can handle as the following:

    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if  message.name == "wired.chat.user_list" {
            print(message.xml(pretty: true))
        }
    }

### Send messages

The following example illustrate how to send a message:

    let message = P7Message(withName: "wired.chat.say", spec: spec)
    message!.addParameter(field: "wired.chat.id", value: 1) // public chat ID
    message!.addParameter(field: "wired.chat.say", value: "Hello, world!")
    
    self.connection.send(message: message!)
    
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
