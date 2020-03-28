//
//  NSMutableAttributedString+BBCodeString.m
//  MRAttributedStringRendering
//
//  Created by Miha Rataj on 2. 03. 13.
//  Copyright (c) 2013 Miha Rataj. All rights reserved.
//

#import "NSMutableAttributedString+BBCodeString.h"

@implementation NSMutableAttributedString (BBCodeString)

- (void)setFont:(NSFont *)font
{
    NSRange range = NSMakeRange(0, [self.string length]);
    [self addAttribute:kCTFontAttributeName
                 value:font
                 range:range];
}

- (void)setColor:(NSColor *)color
{
    NSRange range = NSMakeRange(0, [self.string length]);
    [self addAttribute:kCTForegroundColorAttributeName
                 value:color
                 range:range];
}

@end
