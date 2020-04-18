//
//  BBCodeString.h
//  BBCodeString
//
//  Created by Miha Rataj on 10. 03. 13.
//  Copyright (c) 2013 Miha Rataj. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BBCodeStringDelegate.h"

@class BBElement;

@interface BBCodeString : NSObject {
    NSMutableAttributedString *_attributedString;
    BBElement *_root;
}

@property (nonatomic, weak) id<BBCodeStringDelegate> layoutProvider;
@property (nonatomic, readonly, copy) NSString *bbCode;
@property (nonatomic, readonly) NSMutableAttributedString *attributedString;

- (id)initWithBBCode:(NSString *)bbCode andLayoutProvider:(id<BBCodeStringDelegate>)layoutProvider;

- (BBElement *)getElementByIndex:(NSInteger)characterIndex;

@end
