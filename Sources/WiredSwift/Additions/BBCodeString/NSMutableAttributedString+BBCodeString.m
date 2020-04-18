//
//  NSMutableAttributedString+BBCodeString.m
//  MRAttributedStringRendering
//
//  Created by Miha Rataj on 2. 03. 13.
//  Copyright (c) 2013 Miha Rataj. All rights reserved.
//

#import "NSMutableAttributedString+BBCodeString.h"

#if !TARGET_OS_IOS
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif


@implementation NSMutableAttributedString (BBCodeString)

#if !TARGET_OS_IOS
- (void)setFont:(NSFont *)font
{
    NSRange range = NSMakeRange(0, [self.string length]);
    [self addAttribute:NSFontAttributeName
                 value:font
                 range:range];
}
#else
- (void)setFont:(UIFont *)font
{
    NSRange range = NSMakeRange(0, [self.string length]);
    [self addAttribute:NSFontAttributeName
                 value:font
                 range:range];
}
#endif


#if !TARGET_OS_IOS
- (void)setColor:(NSColor *)color
{
    NSRange range = NSMakeRange(0, [self.string length]);
    [self addAttribute:NSForegroundColorAttributeName
                 value:color
                 range:range];
}
#else
- (void)setColor:(UIColor *)color
{
    NSRange range = NSMakeRange(0, [self.string length]);
    [self addAttribute:NSForegroundColorAttributeName
                 value:color
                 range:range];
}
#endif

@end
