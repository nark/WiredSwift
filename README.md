# Wired Swift

Wired Swift is an implementation of the Wired 2.0 protocol written in Swift.

**WARNING, WiredSwift is a work-in-progress at this moment, and you should not expect anything from it right now. The road to a new Wired codebase is long journey and any help is welcome.**

Wired Swift is primarilly a Swift framework named `WiredSwift` wich provides a very minimal set of classes to manage client connection and basic communication with Wired 2.0 servers. The Wired 2.0 protocol is a binary client/server serialized network protocol implementing BSS-style services like public chat, private messaging and file transfers. It was originally created by Axel Andersson as C/Objective-C codebase which this project tends to translate to pure a Swift implementation.

The main reason for this move is to bootstrap the Wired 2.0 protocol features in a more modern codebase which better scales up to today devices and plateforms. Swift seems to be the perfect candidate since it is now stable, widely documented and even supported by Linux systems. Also, software components like the Wired Client application suffers from many bugs and years of poor maintenance, and their high complexity makes it easier to rewritte everything from scratch instead of trying to fix them.

Maybe this project is the start for a « Wired 3 » version, but without breaking the 2.0 network protocol compatibility, mostly focusing on rewritting the code in another language. With data privacy becoming more and more something difficult to manage, I'm pretty convinced that the BBS scene will regain some interest, at least for those who really care.

## Requirements

* macOS 10.14
* Xcode 

## Getting started

Init dependencies:

    cd WiredSwift
    carthage update

## TODO

* List type in P7 messages: not implemented yet 
* Files browsing: poor native support on macOS
* File transfers: download/upload files and directories with local and remote queue
* Socket compression: not implemented yet (gzip)
* Socket checksum: not implemented yet 
* Auto-reconnection: we jumps for networks to networks these days...
* Better use of user privileges on client side
* Write unit tests and enforce Github actions plan
* Write minimal server code (embed mac server in client? — but still as a separated process)
* Always try to be as close as pure Swift foundation when it relies to Wired framework
* Make Wired a separated repository from the framework with Carthage, Package and Pods support

## License

This code is distributed under BSD license, and it is free for personal or commercial use.
        
- Copyright (c) 2003-2009 Axel Andersson, All rights reserved.
- Copyright (c) 2011-2020 Rafaël Warnault, All rights reserved.
        
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
        
Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
        
THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
