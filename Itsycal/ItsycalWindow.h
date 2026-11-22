//
//  ItsycalWindow.h
//  Itsycal
//
//  Created by Sanjay Madan on 12/14/14.
//  Copyright (c) 2014 mowglii.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, ItsycalGlassStyle) {
    ItsycalGlassStyleRegular = 0,
    ItsycalGlassStyleClear   = 1,
    ItsycalGlassStyleClassic = 2
};

@interface ItsycalWindow : NSPanel

@property (nonatomic, readonly) NSView *hostedContentView;

- (void)positionRelativeToRect:(NSRect)rect screenMaxX:(CGFloat)screenMaxX;
- (void)applyGlassStyle:(ItsycalGlassStyle)style;
- (void)resizeToFitContentAnchoredAtTop;

@end
