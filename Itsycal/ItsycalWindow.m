//
//  ItsycalWindow.m
//  Itsycal
//
//  Created by Sanjay Madan on 12/14/14.
//  Copyright (c) 2014 mowglii.com. All rights reserved.
//

#import "ItsycalWindow.h"
#import <QuartzCore/QuartzCore.h>
#import "Itsycal.h"
#import "Themer.h"

static const CGFloat kMinimumSpaceBetweenWindowAndScreenEdge = 10;
static const CGFloat kFloatingGapBelowMenuBar = 6;
static const CGFloat kCornerRadius = 22;
static const CGFloat kHorizontalPadding = 4;
static const CGFloat kVerticalPadding = 12;

@interface ItsycalWindowFrameView : NSView
@property (nonatomic, readonly) NSView *hostedContentView;
- (void)applyGlassStyle:(ItsycalGlassStyle)style;
@end

#pragma mark -
#pragma mark ItsycalWindow

// =========================================================================
// ItsycalWindow
// =========================================================================

@implementation ItsycalWindow

- (id)init
{
    self = [super initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    if (self) {
        [self setBackgroundColor:[NSColor clearColor]];
        [self setOpaque:NO];
        [self setHasShadow:YES];
        [self setLevel:NSMainMenuWindowLevel];
        [self setMovableByWindowBackground:NO];
        [self setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
        // Fade out when -[NSWindow orderOut:] is called.
        [self setAnimationBehavior:NSWindowAnimationBehaviorUtilityWindow];

        ItsycalWindowFrameView *frameView = [ItsycalWindowFrameView new];
        ItsycalGlassStyle style = (ItsycalGlassStyle)[[NSUserDefaults standardUserDefaults] integerForKey:kDualTZWindowGlassStyle];
        [frameView applyGlassStyle:style];
        [self setContentView:frameView];
    }
    return self;
}

- (NSView *)hostedContentView
{
    ItsycalWindowFrameView *frameView = (ItsycalWindowFrameView *)self.contentView;
    if ([frameView isKindOfClass:[ItsycalWindowFrameView class]]) {
        return frameView.hostedContentView;
    }
    return self.contentView;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)sendEvent:(NSEvent *)event
{
    // When Itsycal is pinned and the user clicks in another app,
    // our window resigns key. AppKit then uses the next click in
    // our window to make it key and swallows that click unless the
    // view under it accepts first mouse. Become key first so the
    // click goes through to whatever view the user clicked.
    if (event.type == NSEventTypeLeftMouseDown && !self.isKeyWindow) {
        [self makeKeyWindow];
    }
    [super sendEvent:event];
}

- (void)positionRelativeToRect:(NSRect)rect screenMaxX:(CGFloat)screenMaxX
{
    // 无尖角悬浮弹窗，距顶部菜单栏保留 6pt 呼吸缝隙
    CGFloat w = NSWidth(self.frame);
    CGFloat x = roundf(NSMidX(rect) - w / 2);
    CGFloat y = NSMinY(rect) - kFloatingGapBelowMenuBar;

    if (x + w + kMinimumSpaceBetweenWindowAndScreenEdge > screenMaxX) {
        x = screenMaxX - w - kMinimumSpaceBetweenWindowAndScreenEdge;
    }

    [self setFrameTopLeftPoint:NSMakePoint(x, y)];
    [self invalidateShadow];
}

- (void)applyGlassStyle:(ItsycalGlassStyle)style
{
    ItsycalWindowFrameView *frameView = (ItsycalWindowFrameView *)self.contentView;
    if ([frameView isKindOfClass:[ItsycalWindowFrameView class]]) {
        [frameView applyGlassStyle:style];
    }
    [self invalidateShadow];
}

@end

#pragma mark -
#pragma mark ItsycalWindowFrameView

// =========================================================================
// ItsycalWindowFrameView
// =========================================================================

@implementation ItsycalWindowFrameView
{
    NSGlassEffectView *_glassView API_AVAILABLE(macos(26.0));
    NSVisualEffectView *_classicBlurView;
    NSView *_classicTintView;
    NSView *_hostedContentView;
    ItsycalGlassStyle _glassStyle;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        self.layer.cornerRadius = kCornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;

        _hostedContentView = [[NSView alloc] initWithFrame:self.bounds];
        _hostedContentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _hostedContentView.wantsLayer = YES;
        _hostedContentView.layer.backgroundColor = NSColor.clearColor.CGColor;
        _hostedContentView.additionalSafeAreaInsets = NSEdgeInsetsMake(kVerticalPadding, kHorizontalPadding, kVerticalPadding, kHorizontalPadding);

        [self setupBackdropLayers];
    }
    return self;
}

- (NSView *)hostedContentView
{
    return _hostedContentView;
}

- (void)setupBackdropLayers
{
    if (@available(macOS 26.0, *)) {
        _glassView = [[NSGlassEffectView alloc] initWithFrame:self.bounds];
        _glassView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _glassView.cornerRadius = kCornerRadius;
        _glassView.style = NSGlassEffectViewStyleRegular;
        [self addSubview:_glassView];
    }

    _classicBlurView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
    _classicBlurView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _classicBlurView.material = NSVisualEffectMaterialPopover;
    _classicBlurView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _classicBlurView.state = NSVisualEffectStateActive;
    _classicBlurView.wantsLayer = YES;
    _classicBlurView.layer.cornerRadius = kCornerRadius;
    _classicBlurView.layer.cornerCurve = kCACornerCurveContinuous;
    _classicBlurView.layer.masksToBounds = YES;

    _classicTintView = [[NSView alloc] initWithFrame:_classicBlurView.bounds];
    _classicTintView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _classicTintView.wantsLayer = YES;
    [_classicBlurView addSubview:_classicTintView];
    [self addSubview:_classicBlurView];
}

- (void)applyGlassStyle:(ItsycalGlassStyle)style
{
    _glassStyle = (style >= ItsycalGlassStyleRegular && style <= ItsycalGlassStyleClassic)
        ? style
        : ItsycalGlassStyleRegular;

    BOOL hasNativeGlass = NO;
    if (@available(macOS 26.0, *)) {
        hasNativeGlass = (_glassView != nil);
    }

    if (hasNativeGlass && _glassStyle != ItsycalGlassStyleClassic) {
        if (@available(macOS 26.0, *)) {
            _classicBlurView.hidden = YES;
            _glassView.hidden = NO;
            _glassView.cornerRadius = kCornerRadius;
            _glassView.style = (_glassStyle == ItsycalGlassStyleClear)
                ? NSGlassEffectViewStyleClear
                : NSGlassEffectViewStyleRegular;
            if (_hostedContentView.superview != _glassView) {
                [_hostedContentView removeFromSuperview];
                _hostedContentView.frame = _glassView.bounds;
                _glassView.contentView = _hostedContentView;
            }
        }
    } else {
        if (@available(macOS 26.0, *)) {
            if (_glassView.contentView == _hostedContentView) {
                _glassView.contentView = nil;
            }
            _glassView.hidden = YES;
        }
        _classicBlurView.hidden = NO;
        if (_hostedContentView.superview != _classicBlurView) {
            [_hostedContentView removeFromSuperview];
            _hostedContentView.frame = _classicBlurView.bounds;
            [_classicBlurView addSubview:_hostedContentView positioned:NSWindowAbove relativeTo:_classicTintView];
        }
    }

    [self refreshBackdropAppearance];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self refreshBackdropAppearance];
}

- (void)refreshBackdropAppearance
{
    BOOL isDark = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;

    if (@available(macOS 26.0, *)) {
        if (_glassView) {
            if (_glassStyle == ItsycalGlassStyleClear) {
                // 通透档附带极轻柔着色，保障密集日历网格的高对比度可读性
                _glassView.tintColor = isDark
                    ? [NSColor colorWithCalibratedWhite:0.06 alpha:0.14]
                    : [NSColor colorWithCalibratedWhite:1.00 alpha:0.12];
            } else {
                _glassView.tintColor = nil;
            }
        }
    }

    NSColor *fallback = [Theme.mainBackgroundColor colorWithAlphaComponent:0.86];
    _classicTintView.layer.backgroundColor = fallback.CGColor;
    self.layer.borderWidth = isDark ? 0.5 : 0.75;
    self.layer.borderColor = (isDark
        ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.18]
        : [NSColor colorWithCalibratedWhite:1.0 alpha:0.55]).CGColor;
}

@end
