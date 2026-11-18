//
//  MoCalGrid.m
//
//
//  Created by Sanjay Madan on 12/3/14.
//  Copyright (c) 2014 mowglii.com. All rights reserved.
//

#import "MoCalGrid.h"
#import "MoCalCell.h"
#import "Sizer.h"

// Holds the cells, top row first, inside the grid's margins. It clips
// them, so a grid shorter than its rows (while the calendar's resize
// handle is dragged) cuts off its bottom row.
@interface MoCalGridCellsView : NSView
@end

@implementation MoCalGridCellsView

- (BOOL)isFlipped
{
    return YES;
}

@end

@implementation MoCalGrid
{
    NSUInteger _rows, _cols, _hMargin, _vMargin;
    BOOL _usesWideCells, _usesTallCells;
    MoCalGridCellsView *_cellsView;
}

- (instancetype)initWithRows:(NSUInteger)rows columns:(NSUInteger)cols horizontalMargin:(NSUInteger)hMargin verticalMargin:(NSUInteger)vMargin
{
    return [self initWithRows:rows columns:cols horizontalMargin:hMargin verticalMargin:vMargin usesWideCells:NO usesTallCells:NO];
}

- (instancetype)initWithRows:(NSUInteger)rows columns:(NSUInteger)cols horizontalMargin:(NSUInteger)hMargin verticalMargin:(NSUInteger)vMargin usesWideCells:(BOOL)usesWideCells usesTallCells:(BOOL)usesTallCells
{
    CGFloat w = usesWideCells ? SizePref.cellWidth : SizePref.cellSize;
    CGFloat h = usesTallCells ? SizePref.cellHeight : SizePref.cellSize;
    self = [super initWithFrame:NSMakeRect(0, 0, w * cols + 2 * hMargin, h * rows + 2 * vMargin)];
    if (self) {
        _rows  = 0;
        _cols  = cols;
        _hMargin = hMargin;
        _vMargin = vMargin;
        _usesWideCells = usesWideCells;
        _usesTallCells = usesTallCells;
        _cells = @[];

        // The autoresizing mask keeps the margins as the grid resizes.
        _cellsView = [[MoCalGridCellsView alloc] initWithFrame:NSInsetRect(self.bounds, hMargin, vMargin)];
        _cellsView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _cellsView.clipsToBounds = YES;
        [self addSubview:_cellsView];

        for (NSUInteger row = 0; row < rows; row++) {
            [self addRow];
        }

        // Hug the cells tightly
        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        
        REGISTER_FOR_SIZE_CHANGE;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (CGFloat)cellW
{
    return _usesWideCells ? SizePref.cellWidth : SizePref.cellSize;
}

- (CGFloat)cellH
{
    return _usesTallCells ? SizePref.cellHeight : SizePref.cellSize;
}

- (void)addRow
{
    NSMutableArray *cells = [_cells mutableCopy];
    CGFloat w = [self cellW];
    CGFloat h = [self cellH];
    BOOL centerText = (_usesWideCells != _usesTallCells);
    for (NSUInteger col = 0; col < _cols; col++) {
        MoCalCell *cell = [MoCalCell new];
        cell.centersTextVertically = centerText;
        [cell setFrame:NSMakeRect(w * col, h * _rows, w, h)];
        [_cellsView addSubview:cell];
        [cells addObject:cell];
    }
    _rows += 1;
    _cells = [NSArray arrayWithArray:cells];
    [self invalidateIntrinsicContentSize];
}

- (void)removeRow
{
    NSMutableArray *cells = [_cells mutableCopy];
    for (NSUInteger col = 0; col < _cols; col++) {
        [cells.lastObject removeFromSuperview];
        [cells removeLastObject];
    }
    _rows -= 1;
    _cells = [NSArray arrayWithArray:cells];
    [self invalidateIntrinsicContentSize];
}

- (MoCalCell *)cellAtPoint:(NSPoint)point
{
    NSPoint p = [_cellsView convertPoint:point fromView:self];
    if (!NSPointInRect(p, _cellsView.bounds)) {
        return nil;
    }
    NSInteger col = floor(p.x / [self cellW]);
    NSInteger row = floor(p.y / [self cellH]);
    if (col < 0 || row < 0 || col >= _cols || row >= _rows) {
        return nil;
    }
    return _cells[_cols * row + col];
}

- (MoCalCell *)cellWithDate:(MoDate)date
{
    for (MoCalCell *cell in self.cells) {
        if (CompareDates(date, cell.date) == 0) {
            return cell;
        }
    }
    return nil;
}

- (NSRect)cellsRect
{
    return _cellsView.frame;
}

- (CGFloat)heightForRows:(NSUInteger)rows
{
    return [self cellH] * rows + 2 * _vMargin;
}

- (CGFloat)rowsForHeight:(CGFloat)height
{
    return (height - 2 * _vMargin) / [self cellH];
}

- (NSSize)intrinsicContentSize
{
    CGFloat width = [self cellW] * _cols + 2 * _hMargin;
    return NSMakeSize(width, [self heightForRows:_rows]);
}

- (void)sizeChanged:(id)sender
{
    CGFloat w = [self cellW];
    CGFloat h = [self cellH];
    for (NSUInteger row = 0; row < _rows; row++) {
        for (NSUInteger col = 0; col < _cols; col++) {
            [_cells[row*_cols + col] setFrame:NSMakeRect(w * col, h * row, w, h)];
        }
    }
    [self invalidateIntrinsicContentSize];
}

@end
