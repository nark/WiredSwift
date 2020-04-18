//
//  NSMutableAttributedString+BBCodeString.h
//  MRAttributedStringRendering
//
//  Created by Miha Rataj on 2. 03. 13.
//  Copyright (c) 2013 Miha Rataj. All rights reserved.
//

#import <Foundation/Foundation.h>

#if !TARGET_OS_IOS
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif

@interface NSMutableAttributedString (BBCodeString)

#if !TARGET_OS_IOS
- (void)setFont:(NSColor *)font;
- (void)setColor:(NSColor *)color;
#else
- (void)setFont:(UIColor *)font;
- (void)setColor:(UIColor *)color;
#endif

@end
