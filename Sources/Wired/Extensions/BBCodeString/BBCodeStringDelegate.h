//
//  BBCodeStringDelegate.h
//  BBCodeString
//
//  Created by Miha Rataj on 10. 03. 13.
//  Copyright (c) 2013 Miha Rataj. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class BBElement;

@protocol BBCodeStringDelegate <NSObject>

@optional

/** Returns the text which will be displayed for the given BBCode element. **/
- (NSString *)getTextForElement:(BBElement *)element;

/** Returns the attributed text which will be displayed for the given BBCode element. **/
- (NSAttributedString *)getAttributedTextForElement:(BBElement *)element;

/** Deprecated. Returns the font for the given BBCode element. **/
- (NSFont *)getFont:(BBElement *)element;

/** Deprecated. Returns the text color for the given BBCode element. **/
- (NSColor *)getTextColor:(BBElement *)element;

@required

/** Returns the whitelist of the BBCode tags your code supports. **/
- (NSArray *)getSupportedTags;

/** Returns the attributes for the part of NSAttributedString which will present the given BBCode element.  **/
- (NSDictionary *)getAttributesForElement:(BBElement *)element;

@end
