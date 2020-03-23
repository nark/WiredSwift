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

import AppKit

open class MessagesViewController: NSViewController {
    
    // MARK: - Properties [Public]

    open var scrollView: NSScrollView!
    
    /// The `MessagesCollectionView` managed by the messages view controller object.
    open var messagesCollectionView = MessagesCollectionView()

    /// A Boolean value that determines whether the `MessagesCollectionView` scrolls to the
    /// bottom whenever the `InputTextView` begins editing.
    ///
    /// The default value of this property is `false`.
    open var scrollsToBottomOnKeybordBeginsEditing: Bool = false
    
    /// A Boolean value that determines whether the `MessagesCollectionView`
    /// maintains it's current position when the height of the `MessageInputBar` changes.
    ///
    /// The default value of this property is `false`.
    open var maintainPositionOnKeyboardFrameChanged: Bool = false

    open override var acceptsFirstResponder: Bool {
        return true
    }

    /// A Boolean value used to determine if `viewDidLayoutSubviews()` has been called.
    private var isFirstLayout: Bool = true
    
    /// Indicated selected indexPath when handle menu action
    var selectedIndexPathForMenu: IndexPath?

//    var messageCollectionViewBottomInset: CGFloat = 0 {
//        didSet {
//            messagesCollectionView.contentInset.bottom = messageCollectionViewBottomInset
//            messagesCollectionView.scrollIndicatorInsets.bottom = messageCollectionViewBottomInset
//        }
//    }

    // MARK: - View Life Cycle

    open override func loadView() {
        self.view = NSView()
        self.view.autoresizesSubviews = true
        self.view.autoresizingMask = [.height, .width]
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        setupDefaults()
        setupSubviews()
        setupConstraints()
        registerReusableViews()
        setupDelegates()
    }

    // MARK: - Initializers


    // MARK: - Methods [Private]

    /// Sets the default values for the MessagesViewController
    private func setupDefaults() {
//        automaticallyAdjustsScrollViewInsets = false
        view.layer?.backgroundColor = .white
//        messagesCollectionView.alwaysBounceVertical = true
    }

    /// Sets the delegate and dataSource of the messagesCollectionView property.
    private func setupDelegates() {
        messagesCollectionView.delegate = self
        messagesCollectionView.dataSource = self
    }

    /// Adds the messagesCollectionView to the controllers root view.
    private func setupSubviews() {
        scrollView = NSScrollView()
        scrollView.autoresizingMask = [.height, .width]
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.autoresizesSubviews = true
        scrollView.scrollsDynamically = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        scrollView.documentView = messagesCollectionView

        self.view.addSubview(self.scrollView)
    }

    /// Registers all cells and supplementary views of the messagesCollectionView property.
    private func registerReusableViews() {
        messagesCollectionView.register(TextMessageItem.self)
        messagesCollectionView.register(MediaMessageItem.self)
        messagesCollectionView.register(LocationMessageItem.self)

        messagesCollectionView.register(MessageFooterView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionFooter)
        messagesCollectionView.register(MessageHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader)
        messagesCollectionView.register(MessageDateHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader)
    }

    /// Sets the constraints of the `MessagesCollectionView`.
    private func setupConstraints() {
        view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor).isActive = true
        view.topAnchor.constraint(equalTo: scrollView.topAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor).isActive = true
    }
}
