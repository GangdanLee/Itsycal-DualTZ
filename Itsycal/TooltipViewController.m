//
//  TooltipViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/17/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "TooltipViewController.h"
#import "Itsycal.h"
#import "Themer.h"
#import "Sizer.h"

static NSString *kMoreCellIdentifier = @"TooltipMoreCell";
static const CGFloat kRowsOverhang = 3;
static const CGFloat kRowsInset = 2;

@interface TooltipMoreRow : NSObject
@property (nonatomic) NSInteger count;
@end

@implementation TooltipMoreRow
@end

@interface TooltipMoreCell : NSView
@property (nonatomic) NSTextField *textField;
- (void)updateSize;
@end

@implementation TooltipMoreCell
{
    NSLayoutConstraint *_leadingConstraint;
}

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.identifier = kMoreCellIdentifier;
        _textField = [NSTextField labelWithString:@""];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.textColor = Theme.agendaEventDateTextColor;
        [self addSubview:_textField];
        _leadingConstraint = [_textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];
        _leadingConstraint.active = YES;
        [_textField.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-11].active = YES;
        [_textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [self updateSize];
    }
    return self;
}

- (void)updateSize
{
    _textField.font = [NSFont systemFontOfSize:SizePref.fontSize];
    _leadingConstraint.constant = SizePref.agendaEventLeadingMargin;
}

@end

@interface TooltipViewController ()
@property (nonatomic, readonly) NSView *tooltipView;
- (NSSize)layoutEvents:(NSArray *)events headerText:(NSString *)headerText maxHeight:(CGFloat)maxHeight;
@end

@interface TooltipDayContent : NSObject <TooltipContent>
@property (nonatomic, copy) NSArray *events;
@property (nonatomic, copy) NSString *headerText;
@property (nonatomic) TooltipViewController *viewController;
@end

@implementation TooltipDayContent

- (NSView *)tooltipView
{
    return self.viewController.tooltipView;
}

- (NSSize)layoutTooltipViewWithMaxHeight:(CGFloat)maxHeight
{
    return [self.viewController layoutEvents:self.events headerText:self.headerText maxHeight:maxHeight];
}

@end

@implementation TooltipViewController
{
    NSView *_container;
    NSTextField *_headerLabel;
    NSView *_headerDivider;
}

- (id<TooltipContent>)tooltipContentForEvents:(NSArray *)events
{
    return [self tooltipContentForEvents:events headerText:nil];
}

- (id<TooltipContent>)tooltipContentForEvents:(NSArray *)events headerText:(NSString *)headerText
{
    TooltipDayContent *content = [TooltipDayContent new];
    content.events = events;
    content.headerText = headerText;
    content.viewController = self;
    return content;
}

- (void)loadView
{
    [super loadView];
    self.tv.enableHover = NO;
    _container = [NSView new];

    _headerLabel = [NSTextField wrappingLabelWithString:@""];
    _headerLabel.maximumNumberOfLines = 2;
    _headerLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _headerLabel.hidden = YES;

    _headerDivider = [NSView new];
    _headerDivider.wantsLayer = YES;
    _headerDivider.hidden = YES;

    [_container addSubview:self.view];
    [_container addSubview:_headerLabel];
    [_container addSubview:_headerDivider];
}

- (void)viewDidLayout
{
    // Tooltips handle height manually in -layoutEvents:headerText:maxHeight:.
}

- (NSView *)tooltipView
{
    [self loadViewIfNeeded];
    return _container;
}

- (NSSize)layoutEvents:(NSArray *)events headerText:(NSString *)headerText maxHeight:(CGFloat)maxHeight
{
    [self loadViewIfNeeded];
    CGFloat width = SizePref.tooltipWidth;
    BOOL hasHeader = headerText.length > 0;
    CGFloat headerBlockH = 0;
    CGFloat labelH = 0;

    if (hasHeader) {
        _headerLabel.stringValue = headerText;
        _headerLabel.font = [NSFont systemFontOfSize:MAX(10.5, SizePref.fontSize - 1.5) weight:NSFontWeightMedium];
        _headerLabel.textColor = Theme.todayCellColor;
        _headerLabel.preferredMaxLayoutWidth = width - 16;
        labelH = ceil([_headerLabel sizeThatFits:NSMakeSize(width - 16, 80)].height);
        _headerLabel.hidden = NO;
        _headerDivider.layer.backgroundColor = Theme.agendaDividerColor.CGColor;
        _headerDivider.hidden = (events.count == 0);
        headerBlockH = 6 + labelH + (events.count > 0 ? 9 : 6);
    } else {
        _headerLabel.hidden = YES;
        _headerDivider.hidden = YES;
    }

    NSView *rowsView = self.view;
    CGFloat rowsHeight = 0;
    if (events.count > 0) {
        rowsView.hidden = NO;
        rowsHeight = [self measureAndPopulateEvents:events width:width maxAvailable:(maxHeight - 2 * kRowsInset - headerBlockH)];
        rowsView.frame = NSMakeRect(-kRowsOverhang, kRowsInset, width + 2 * kRowsOverhang, rowsHeight);
    } else {
        rowsView.hidden = YES;
        self.events = @[];
        [self.tv reloadData];
    }

    CGFloat containerH = headerBlockH + (events.count > 0 ? rowsHeight + (hasHeader ? kRowsInset : 2 * kRowsInset) : 0);
    if (hasHeader) {
        _headerLabel.frame = NSMakeRect(8, containerH - 6 - labelH, width - 16, labelH);
        _headerDivider.frame = NSMakeRect(8, containerH - headerBlockH + 4, width - 16, 1);
    }
    _container.frame = NSMakeRect(0, 0, width, containerH);
    [_container layoutSubtreeIfNeeded];
    [self scrollToTop];
    return _container.frame.size;
}

- (CGFloat)measureAndPopulateEvents:(NSArray *)events width:(CGFloat)width maxAvailable:(CGFloat)available
{
    NSView *rowsView = self.view;
    rowsView.frame = NSMakeRect(-kRowsOverhang, kRowsInset, width + 2 * kRowsOverhang, MAX(NSHeight(rowsView.frame), 1));
    [rowsView layoutSubtreeIfNeeded];

    self.events = events;
    NSMutableArray<NSNumber *> *heights = [NSMutableArray new];
    CGFloat total = 0;
    for (NSInteger row = 0; row < (NSInteger)events.count; row++) {
        CGFloat h = [self tableView:self.tv heightOfRow:row];
        [heights addObject:@(h)];
        total += h;
    }

    NSArray *rows = events;
    if (total > available && available > 0) {
        CGFloat moreH = [self moreRowHeight];
        CGFloat used = 0;
        NSInteger shown = 0;
        while (shown < (NSInteger)events.count && used + heights[shown].doubleValue + moreH <= available) {
            used += heights[shown].doubleValue;
            shown++;
        }
        TooltipMoreRow *more = [TooltipMoreRow new];
        more.count = events.count - shown;
        rows = [[events subarrayWithRange:NSMakeRange(0, shown)] arrayByAddingObject:more];
        total = used + moreH;
    }
    self.events = rows;
    [self.tv reloadData];
    return ceil(total);
}

- (CGFloat)moreRowHeight
{
    static NSTextField *measure = nil;
    if (measure == nil) {
        measure = [NSTextField labelWithString:@"0"];
    }
    measure.font = [NSFont systemFontOfSize:SizePref.fontSize];
    return ceil(measure.fittingSize.height) + 6;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    id obj = self.events[row];
    if (![obj isKindOfClass:[TooltipMoreRow class]]) {
        return [super tableView:tableView viewForTableColumn:tableColumn row:row];
    }
    TooltipMoreCell *cell = [tableView makeViewWithIdentifier:kMoreCellIdentifier owner:self];
    if (cell == nil) cell = [TooltipMoreCell new];
    [cell updateSize];
    NSString *count = [NSNumberFormatter localizedStringFromNumber:@(((TooltipMoreRow *)obj).count) numberStyle:NSNumberFormatterDecimalStyle];
    NSString *format = DualTZLocalizedString(@"%@ more events", @"%@ more");
    cell.textField.stringValue = [NSString stringWithFormat:format, count];
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if ([self.events[row] isKindOfClass:[TooltipMoreRow class]]) {
        return [self moreRowHeight];
    }
    return [super tableView:tableView heightOfRow:row];
}

@end
