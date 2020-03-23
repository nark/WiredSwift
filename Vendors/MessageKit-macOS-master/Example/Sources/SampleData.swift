/*
 MIT License
 
 Copyright (c) 2017-2018 MessageKit
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import MessageKit_macOS
import CoreLocation

final class SampleData {
  
  static let shared = SampleData()
  
  private init() {}
  
  var showTextMessages = true
  var showAttributedTextMessages = true
  var showImageMessages = true
  var showLocationMessages = true
  var showEmojiMessages = true
  
  let messageTextValues = [
    "Ok",
    "k",
    "lol",
    "1-800-555-0000",
    "One Infinite Loop Cupertino, CA 95014 This is some extra text that should not be detected.",
    "This is an example of the date detector 11/11/2017. April 1st is April Fools Day. Next Friday is not Friday the 13th.",
    "https://github.com/SD10",
    "Check out this awesome UI library for Chat",
    "My favorite things in life don’t cost any money. It’s really clear that the most precious resource we all have is time.",
    """
        You know, this iPhone, as a matter of fact, the engine in here is made in America.
        And not only are the engines in here made in America, but engines are made in America and are exported.

        The glass on this phone is made in Kentucky. And so we've been working for years on doing more and more in the United States.
        """,
    """
        Sentence 1
        Sentence 2
        Sentence 3
        Sentence 4
        Sentence 5
        Sentence 6
        """,
    """
        Remembering that I'll be dead soon is the most important tool I've ever encountered to help me make the big choices in life.
        Because almost everything - all external expectations, all pride, all fear of embarrassment or failure -
        these things just fall away in the face of death, leaving only what is truly important.
        """,
    "I think if you do something and it turns out pretty good, then you should go do something else wonderful, not dwell on it for too long. Just figure out what’s next.",
    "Price is rarely the most important thing. A cheap product might sell some units. Somebody gets it home and they feel great when they pay the money, but then they get it home and use it and the joy is gone.",
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nam mattis justo quis nisl dignissim, tincidunt varius ligula fermentum. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Sed rhoncus tristique bibendum. Nulla iaculis urna quis maximus porta. Phasellus tempor gravida finibus. Aenean nec gravida urna. Sed sit amet felis sodales, imperdiet tortor ut, vehicula massa. Aenean vel risus sollicitudin velit feugiat porttitor. Vestibulum facilisis enim nibh, nec rhoncus massa ultrices nec. Pellentesque quam nibh, tempus et rutrum sit amet, lacinia a sapien. Nunc eu nisi id sapien faucibus bibendum. Vestibulum sit amet fringilla eros. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Phasellus imperdiet facilisis augue, at facilisis erat aliquam sed. Suspendisse quis risus id ipsum auctor pharetra sit amet eget nunc. Sed venenatis justo tincidunt, egestas erat eu, consequat lorem. Phasellus vitae tincidunt ante, eu faucibus libero. Aliquam rhoncus orci sed sem lobortis, ac molestie nisl feugiat. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Mauris eu mi eu purus pretium fringilla non sed felis. Nunc eu purus id diam euismod condimentum et vitae lectus."
  ]
  
  let dan = Sender(id: "123456", displayName: "Dan Leonard")
  let steven = Sender(id: "654321", displayName: "Steven")
  let jobs = Sender(id: "000001", displayName: "Steve Jobs")
  let cook = Sender(id: "656361", displayName: "Tim Cook")
  
  lazy var senders = [dan, steven, jobs, cook]
  
  var currentSender: Sender {
    return steven
  }
  
  let messageImages: [NSImage] = [#imageLiteral(resourceName: "Appearance"), #imageLiteral(resourceName: "Banlist"), #imageLiteral(resourceName: "NowPlaying")]
  
  var now = Date()
  
  let messageTypes = ["Text", "Text", "Text", "AttributedText", "AttributedText", "Photo", "Video", "Location", "Emoji"]
  
  let attributes = ["Font1", "Font2", "Font3", "Font4", "Color", "Combo"]
  
  let locations: [CLLocation] = [
    CLLocation(latitude: 37.3118, longitude: -122.0312),
    CLLocation(latitude: 33.6318, longitude: -100.0386),
    CLLocation(latitude: 29.3358, longitude: -108.8311),
    CLLocation(latitude: 38.8894838, longitude: -77.03527910000003) // Washington monument
  ]
  
  let emojis = [
    "👍",
    "👋",
    "👋👋👋",
    "😱😱",
    "🎈",
    "🇧🇷"
  ]
  
  func attributedString(with text: String, andType attributeType: String) -> NSAttributedString {
    let nsString = NSString(string: text)
    var mutableAttributedString = NSMutableAttributedString(string: text)
    let range = NSRange(location: 0, length: nsString.length)
    
    switch attributeType {
    case "Font1":
      mutableAttributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.userFont(ofSize: 20)!, range: range)
    case "Font2":
      mutableAttributedString.addAttributes([NSAttributedString.Key.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: NSFont.Weight.bold)], range: range)
    case "Font3":
      mutableAttributedString.addAttributes([NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)], range: range)
    case "Font4":
      mutableAttributedString.addAttributes([NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)], range: range)
    case "Color":
      mutableAttributedString.addAttributes([NSAttributedString.Key.foregroundColor: NSColor.red], range: range)
    case "Combo":
      let msg9String = "Use .attributedText() to add bold, italic, colored text and more..."
      let msg9Text = NSString(string: msg9String)
      let msg9AttributedText = NSMutableAttributedString(string: String(msg9Text))
      
      msg9AttributedText.addAttribute(NSAttributedString.Key.font, value: NSFont.messageFont(ofSize: NSFont.systemFontSize), range: NSRange(location: 0, length: msg9Text.length))
      msg9AttributedText.addAttributes([NSAttributedString.Key.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: NSFont.Weight.bold)], range: msg9Text.range(of: ".attributedText()"))
      msg9AttributedText.addAttributes([NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)], range: msg9Text.range(of: "bold"))
      msg9AttributedText.addAttributes([NSAttributedString.Key.foregroundColor: NSColor.red], range: msg9Text.range(of: "colored"))
      mutableAttributedString = msg9AttributedText
    default:
      fatalError("Unrecognized attribute for mock message")
    }
    
    return NSAttributedString(attributedString: mutableAttributedString)
  }
  
  func dateAddingRandomTime() -> Date {
    let randomNumber = Int.random(in: 0..<10)
    if randomNumber % 2 == 0 {
      let date = Calendar.current.date(byAdding: .hour, value: randomNumber, to: now)!
      now = date
      return date
    } else {
      let randomMinute = Int.random(in: 0..<59)
      let date = Calendar.current.date(byAdding: .minute, value: randomMinute, to: now)!
      now = date
      return date
    }
  }
  
  func randomMessage() -> ChatMessage {
    
    switch messageTypes.randomElement()! {
    case "Text":
      return ChatMessage(text: messageTextValues.randomElement()!,
                         sender: senders.randomElement()!,
                         messageId: newMessageId(),
                         date: dateAddingRandomTime())
    case "AttributedText":
      let text = messageTextValues.randomElement()!
      let attributeType = attributes.randomElement()!
      let attributedText = attributedString(with: text, andType: attributeType)
      return ChatMessage(attributedText: attributedText,
                         sender: senders.randomElement()!,
                         messageId: newMessageId(),
                         date: dateAddingRandomTime())
    case "Photo":
      let image = messageImages.randomElement()!
      return ChatMessage(image: image,
                         sender: senders.randomElement()!,
                         messageId: newMessageId(),
                         date: dateAddingRandomTime())
    case "Video":
      let image = messageImages.randomElement()!
      return ChatMessage(thumbnail: image,
                         sender: senders.randomElement()!,
                         messageId: newMessageId(),
                         date: dateAddingRandomTime())
    case "Location":
      return ChatMessage(location: locations.randomElement()!,
                         sender: senders.randomElement()!,
                         messageId: newMessageId(),
                         date: dateAddingRandomTime())
    case "Emoji":
      return ChatMessage(emoji: emojis.randomElement()!,
                         sender: senders.randomElement()!,
                         messageId: newMessageId(),
                         date: dateAddingRandomTime())
    default:
      fatalError("Unrecognized mock message type")
    }
  }
  
  private func newMessageId() -> String {
    return NSUUID().uuidString
  }
  
  func getMessages(count: Int, completion: ([ChatMessage]) -> Void) {
    var messages: [ChatMessage] = []
    for i in 0..<count {
      let message = randomMessage()
      switch message.data {
      case .attributedText(let attributedText):
        print("Message \(i) is attributedText: \(attributedText)")
      case .emoji(_):
        print("Message \(i) is an emoji")
      case .location(_):
        print("Message \(i) is a location")
      case .photo(_):
        print("Message \(i) is a photo")
      case .text(let text):
        print("Message \(i) is text: \(text)")
      case .video(_, _):
        print("Message \(i) is a video")
      }
      messages.append(message)
    }
    completion(messages)
  }
  
  
  func getMessages(completion: ([ChatMessage]) -> Void) {
    var messages: [ChatMessage] = []
    
    
    if showTextMessages {
      for messageText in messageTextValues {
        let msg = ChatMessage(text: messageText,
                              sender: senders.randomElement()!,
                              messageId: newMessageId(),
                              date: dateAddingRandomTime())
        messages.append(msg)
      }
    }
    
    if showAttributedTextMessages {
      for messageText in messageTextValues {
        for attributeType in attributes {
          let attributedText = attributedString(with: messageText, andType: attributeType)
          let msg = ChatMessage(attributedText: attributedText,
                                sender: senders.randomElement()!,
                                messageId: newMessageId(),
                                date: dateAddingRandomTime())
          messages.append(msg)
        }
      }
    }
    
    if showImageMessages {
      for image in messageImages {
        let msg = ChatMessage(image: image,
                              sender: senders.randomElement()!,
                              messageId: newMessageId(),
                              date: dateAddingRandomTime())
        messages.append(msg)
      }
    }
    
    if showLocationMessages {
      for location in locations {
        let msg = ChatMessage(location: location,
                              sender: senders.randomElement()!,
                              messageId: newMessageId(),
                              date: dateAddingRandomTime())
        messages.append(msg)
      }
    }
    
    if showEmojiMessages {
      for emoji in emojis {
        let msg = ChatMessage(emoji: emoji,
                              sender: senders.randomElement()!,
                              messageId: newMessageId(),
                              date: dateAddingRandomTime())
        messages.append(msg)
      }
    }
    
    completion(messages)
  }
  
  
  func getAvatarFor(sender: Sender) -> Avatar {
    switch sender {
    case dan:
      return Avatar(image: #imageLiteral(resourceName: "Smileys"), initials: "DL")
    case steven:
      return Avatar(initials: "SJ")
    case jobs:
      return Avatar(image: #imageLiteral(resourceName: "Smileys"), initials: "SJ")
    case cook:
      return Avatar(image: #imageLiteral(resourceName: "Smileys"))
    default:
      return Avatar()
    }
  }
  
}
