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
{
    BOOL _isResizingToFit;
}

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
    [self resizeToFitContentAnchoredAtTop];

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

- (void)resizeToFitContentAnchoredAtTop
{
    if (_isResizingToFit) return;
    _isResizingToFit = YES;

    NSView *content = self.contentView;
    NSView *hosted = self.hostedContentView;
    if (!content || !hosted) {
        _isResizingToFit = NO;
        return;
    }

    [content layoutSubtreeIfNeeded];
    NSSize desired = hosted.fittingSize;
    if (desired.width < 280) {
        desired = content.fittingSize;
    }

    NSScreen *scr = self.screen ?: NSScreen.mainScreen;
    CGFloat maxH = scr ? MAX(320.0, NSHeight(scr.visibleFrame) - 36.0) : 860.0;
    CGFloat targetW = MAX(ceil(desired.width), 310.0);
    CGFloat targetH = MIN(MAX(ceil(desired.height), 240.0), maxH);

    NSRect oldFrame = self.frame;
    if (fabs(NSWidth(oldFrame) - targetW) > 0.5 || fabs(NSHeight(oldFrame) - targetH) > 0.5) {
        CGFloat topY = NSHeight(oldFrame) > 10.0 ? NSMaxY(oldFrame) : (scr ? NSMaxY(scr.visibleFrame) - kFloatingGapBelowMenuBar : 800.0);
        CGFloat originY = topY - targetH;
        if (scr) {
            CGFloat minAllowedY = NSMinY(scr.visibleFrame) + 8.0;
            if (originY < minAllowedY) {
                originY = minAllowedY;
            }
        }
        NSRect newFrame = NSMakeRect(NSMinX(oldFrame), originY, targetW, targetH);
        [self setFrame:newFrame display:YES];
        [content layoutSubtreeIfNeeded];
        [self invalidateShadow];
    }

    _isResizingToFit = NO;
}

- (void)applyGlassStyle:(ItsycalGlassStyle)style
{
    ItsycalWindowFrameView *frameView = (ItsycalWindowFrameView *)self.contentView;
    if ([frameView isKindOfClass:[ItsycalWindowFrameView class]]) {
        [frameView applyGlassStyle:style];
    }
    [self resizeToFitContentAnchoredAtTop];
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
    NSArray<NSLayoutConstraint *> *_hostedConstraints;
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

        _hostedContentView = [NSView new];
        _hostedContentView.translatesAutoresizingMaskIntoConstraints = NO;
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

- (void)pinView:(NSView *)child toEdgesOf:(NSView *)parent
{
    [NSLayoutConstraint activateConstraints:@[
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor]
    ]];
}

- (void)setupBackdropLayers
{
    if (@available(macOS 26.0, *)) {
        _glassView = [NSGlassEffectView new];
        _glassView.translatesAutoresizingMaskIntoConstraints = NO;
        _glassView.cornerRadius = kCornerRadius;
        _glassView.style = NSGlassEffectViewStyleRegular;
        [self addSubview:_glassView];
        [self pinView:_glassView toEdgesOf:self];
    }

    _classicBlurView = [NSVisualEffectView new];
    _classicBlurView.translatesAutoresizingMaskIntoConstraints = NO;
    _classicBlurView.material = NSVisualEffectMaterialPopover;
    _classicBlurView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _classicBlurView.state = NSVisualEffectStateActive;
    _classicBlurView.wantsLayer = YES;
    _classicBlurView.layer.cornerRadius = kCornerRadius;
    _classicBlurView.layer.cornerCurve = kCACornerCurveContinuous;
    _classicBlurView.layer.masksToBounds = YES;

    _classicTintView = [NSView new];
    _classicTintView.translatesAutoresizingMaskIntoConstraints = NO;
    _classicTintView.wantsLayer = YES;
    [_classicBlurView addSubview:_classicTintView];
    [self pinView:_classicTintView toEdgesOf:_classicBlurView];

    [self addSubview:_classicBlurView];
    [self pinView:_classicBlurView toEdgesOf:self];
}

- (void)attachHostedContentToContainer:(NSView *)container
{
    if (_hostedConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:_hostedConstraints];
        _hostedConstraints = nil;
    }
    _hostedConstraints = @[
        [_hostedContentView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_hostedContentView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_hostedContentView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_hostedContentView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor]
    ];
    [NSLayoutConstraint activateConstraints:_hostedConstraints];
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
            if (_glassView.contentView != _hostedContentView) {
                if (_hostedConstraints.count > 0) {
                    [NSLayoutConstraint deactivateConstraints:_hostedConstraints];
                    _hostedConstraints = nil;
                }
                [_hostedContentView removeFromSuperview];
                _glassView.contentView = _hostedContentView;
                if (_hostedContentView.superview) {
                    [self attachHostedContentToContainer:_hostedContentView.superview];
                }
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
            if (_hostedConstraints.count > 0) {
                [NSLayoutConstraint deactivateConstraints:_hostedConstraints];
                _hostedConstraints = nil;
            }
            [_hostedContentView removeFromSuperview];
            [_classicBlurView addSubview:_hostedContentView positioned:NSWindowAbove relativeTo:_classicTintView];
            [self attachHostedContentToContainer:_classicBlurView];
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
