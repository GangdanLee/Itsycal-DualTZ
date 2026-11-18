//
//  MoCalCell.m
//
//
//  Created by Sanjay Madan on 12/3/14.
//  Copyright (c) 2014 mowglii.com. All rights reserved.
//

#import "MoCalCell.h"
#import "Themer.h"
#import "Sizer.h"

@implementation MoCalCell
{
    NSLayoutConstraint *_textFieldVerticalSpace;
    NSLayoutConstraint *_textFieldCenterYConstraint;
    NSLayoutConstraint *_subtitleTopConstraint;
    NSTextField *_subtitleField;
    NSTextField *_badgeField;
}

- (instancetype)init
{
    CGFloat w = SizePref.cellWidth;
    CGFloat h = SizePref.cellHeight;
    self = [super initWithFrame:NSMakeRect(0, 0, w, h)];
    if (self) {
        _textField = [NSTextField labelWithString:@""];
        _textField.font = [NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightMedium];
        _textField.textColor = Theme.currentMonthTextColor;
        _textField.alignment = NSTextAlignmentCenter;
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_textField];

        _subtitleField = [NSTextField labelWithString:@""];
        _subtitleField.font = [NSFont systemFontOfSize:SizePref.subtitleFontSize weight:NSFontWeightRegular];
        _subtitleField.alignment = NSTextAlignmentCenter;
        _subtitleField.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleField.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleField.hidden = YES;
        [self addSubview:_subtitleField];

        _badgeField = [NSTextField labelWithString:@""];
        _badgeField.alignment = NSTextAlignmentRight;
        _badgeField.translatesAutoresizingMaskIntoConstraints = NO;
        _badgeField.hidden = YES;
        [self addSubview:_badgeField];

        _textFieldVerticalSpace = [NSLayoutConstraint constraintWithItem:_textField attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTop multiplier:1 constant:SizePref.cellTextFieldVerticalSpace];
        _textFieldCenterYConstraint = [_textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];
        _subtitleTopConstraint = [_subtitleField.topAnchor constraintEqualToAnchor:_textField.bottomAnchor constant:[self subtitleTopGap]];

        [NSLayoutConstraint activateConstraints:@[
            [_textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            _textFieldVerticalSpace,
            [_subtitleField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [_subtitleField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2],
            _subtitleTopConstraint,
            [_badgeField.topAnchor constraintEqualToAnchor:self.topAnchor constant:1.5],
            [_badgeField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2.0]
        ]];

        REGISTER_FOR_SIZE_CHANGE;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (CGFloat)subtitleTopGap
{
    return SizePref.sizePreference == SizePreferenceSmall ? -1.5 : -1.0;
}

- (void)sizeChanged:(id)sender
{
    NSFontWeight w = self.isBeijingToday ? NSFontWeightSemibold : NSFontWeightMedium;
    _textField.font = [NSFont systemFontOfSize:SizePref.fontSize weight:w];
    _textFieldVerticalSpace.constant = SizePref.cellTextFieldVerticalSpace;
    _subtitleField.font = [NSFont systemFontOfSize:SizePref.subtitleFontSize weight:NSFontWeightRegular];
    _subtitleTopConstraint.constant = [self subtitleTopGap];
    [self updateBadgeTypography];
}

- (void)setCentersTextVertically:(BOOL)centersTextVertically
{
    if (_centersTextVertically != centersTextVertically) {
        _centersTextVertically = centersTextVertically;
        _textFieldVerticalSpace.active = !centersTextVertically;
        _textFieldCenterYConstraint.active = centersTextVertically;
    }
}

- (void)setSubtitleText:(NSString *)subtitleText
{
    NSString *next = subtitleText ?: @"";
    if (![_subtitleField.stringValue isEqualToString:next]) {
        _subtitleField.stringValue = next;
    }
    _subtitleText = [next copy];
    _subtitleField.hidden = (next.length == 0);
}

- (void)setSubtitleStyle:(NSInteger)subtitleStyle
{
    _subtitleStyle = subtitleStyle;
    [self updateAnnotationColors];
}

- (void)setBadgeText:(NSString *)badgeText
{
    NSString *next = badgeText ?: @"";
    if (![_badgeField.stringValue isEqualToString:next]) {
        _badgeField.stringValue = next;
    }
    _badgeText = [next copy];
    _badgeField.hidden = (next.length == 0);
    [self updateBadgeTypography];
}

- (void)setBadgeStyle:(NSInteger)badgeStyle
{
    _badgeStyle = badgeStyle;
    [self updateAnnotationColors];
}

- (void)setIsToday:(BOOL)isToday
{
    _isToday = isToday;
    [self setNeedsDisplay:YES];
}

- (void)setIsBeijingToday:(BOOL)isBeijingToday
{
    if (isBeijingToday != _isBeijingToday) {
        _isBeijingToday = isBeijingToday;
        NSFontWeight w = isBeijingToday ? NSFontWeightSemibold : NSFontWeightMedium;
        _textField.font = [NSFont systemFontOfSize:SizePref.fontSize weight:w];
        [self updateTextColor];
        [self setNeedsDisplay:YES];
    }
}

- (void)setUseSubtleTodayOutline:(BOOL)useSubtleTodayOutline
{
    if (useSubtleTodayOutline != _useSubtleTodayOutline) {
        _useSubtleTodayOutline = useSubtleTodayOutline;
        [self setNeedsDisplay:YES];
    }
}

- (void)setIsHighlighted:(BOOL)isHighlighted
{
    _isHighlighted = isHighlighted;
    [self updateTextColor];
}

- (void)setIsInCurrentMonth:(BOOL)isInCurrentMonth
{
    _isInCurrentMonth = isInCurrentMonth;
    [self updateTextColor];
    [self updateAnnotationColors];
}

- (void)setIsSelected:(BOOL)isSelected
{
    if (isSelected != _isSelected) {
        _isSelected = isSelected;
        [self setNeedsDisplay:YES];
    }
}

- (void)setIsHovered:(BOOL)isHovered
{
    if (isHovered != _isHovered) {
        _isHovered = isHovered;
        [self setNeedsDisplay:YES];
    }
}

- (void)setDotColors:(NSArray<NSColor *> *)dotColors
{
    _dotColors = dotColors;
    [self setNeedsDisplay:YES];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateTextColor];
    [self updateAnnotationColors];
}

- (void)updateBadgeTypography
{
    SizePreference sp = SizePref.sizePreference;
    BOOL isUS = [_badgeField.stringValue isEqualToString:@"US"];
    CGFloat pt;
    if (isUS) {
        pt = (sp == SizePreferenceSmall) ? 6.0 : (sp == SizePreferenceMedium ? 6.5 : 7.0);
    } else {
        pt = (sp == SizePreferenceSmall) ? 7.0 : (sp == SizePreferenceMedium ? 7.5 : 8.0);
    }
    _badgeField.font = [NSFont systemFontOfSize:pt weight:NSFontWeightSemibold];
}

- (void)updateTextColor
{
    if (self.isBeijingToday) {
        self.textField.textColor = Theme.todayCellColor;
        return;
    }
    self.textField.textColor = self.isInCurrentMonth ? Theme.currentMonthTextColor : Theme.noncurrentMonthTextColor;
}

- (void)updateAnnotationColors
{
    // 动态语义色在非绘制期不可调用 colorWithAlphaComponent，否则暗黑模式下动态颜色会失真固化为亮色黑灰
    if (self.subtitleStyle == 1) {
        _subtitleField.textColor = NSColor.systemBlueColor;
    } else if (self.subtitleStyle == 2) {
        _subtitleField.textColor = NSColor.systemRedColor;
    } else if (self.subtitleStyle == 3) {
        _subtitleField.textColor = NSColor.systemOrangeColor;
    } else {
        _subtitleField.textColor = NSColor.secondaryLabelColor;
    }
    _subtitleField.alphaValue = self.isInCurrentMonth ? 1.0 : 0.45;

    if (self.badgeStyle == 1) {
        _badgeField.textColor = NSColor.systemGreenColor;
    } else if (self.badgeStyle == 2) {
        _badgeField.textColor = NSColor.systemRedColor;
    } else {
        _badgeField.textColor = NSColor.secondaryLabelColor;
    }
    _badgeField.alphaValue = self.isInCurrentMonth ? (self.badgeStyle == 0 ? 0.65 : 0.90) : 0.40;
}

- (void)drawRect:(NSRect)dirtyRect
{
    CGFloat radius = SizePref.cellRadius;
    CGFloat inset = SizePref.showsCellSubtitles ? 2.0 : 3.0;
    NSRect r = NSInsetRect(self.bounds, inset, inset);
    if (self.isBeijingToday) {
        // 北京今日：蓝色实线圆角框 + 柔和淡蓝底色（不加多余“京”字）
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];
        [[Theme.todayCellColor colorWithAlphaComponent:(self.isSelected ? 0.22 : 0.13)] setFill];
        [p fill];
        [Theme.todayCellColor setStroke];
        [p setLineWidth:1.5];
        [p stroke];
    }
    else if (self.isToday) {
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];
        if (self.isSelected) {
            [[Theme.currentMonthOutlineColor colorWithAlphaComponent:0.12] setFill];
            [p fill];
        }
        if (self.useSubtleTodayOutline) {
            [[Theme.currentMonthOutlineColor colorWithAlphaComponent:0.65] setStroke];
            [p setLineWidth:1.5];
        } else {
            [Theme.todayCellColor setStroke];
            [p setLineWidth:2];
        }
        [p stroke];
    }
    else if (self.isSelected) {
        // 点选普通日期采用半透明自适应高对比底色，在周末灰列上依然清晰可辨
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];
        [[Theme.currentMonthOutlineColor colorWithAlphaComponent:0.12] setFill];
        [p fill];
    }
    else if (self.isHovered) {
        // 鼠标悬停采用柔和浅底色高亮，避免与“美西今日”的空心边框混淆
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];
        [[Theme.currentMonthOutlineColor colorWithAlphaComponent:0.06] setFill];
        [p fill];
    }
    if (self.dotColors) {
        [self drawEventDots];
    }
}

- (void)drawEventDots
{
    CGFloat w = NSWidth(self.bounds);
    CGFloat dotWidth = SizePref.cellDotWidth;
    CGFloat dotSpacing = 1.5 * dotWidth;
    NSRect dotRect = NSMakeRect(0, 0, dotWidth, dotWidth);
    dotRect.origin.y = self.bounds.origin.y + (SizePref.showsCellSubtitles ? 3.5 : (dotWidth + 2.0));

    NSUInteger count = MIN(self.dotColors.count, (NSUInteger)3);
    if (count == 0) {
        [self.textField.textColor set];
        dotRect.origin.x = self.bounds.origin.x + w / 2.0 - dotWidth / 2.0;
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];
        return;
    }
    CGFloat totalSpan = (count - 1) * dotSpacing;
    CGFloat firstX = self.bounds.origin.x + w / 2.0 - totalSpan / 2.0 - dotWidth / 2.0;
    for (NSUInteger i = 0; i < count; i++) {
        [self.dotColors[i] set];
        dotRect.origin.x = firstX + i * dotSpacing;
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];
    }
}

@end
