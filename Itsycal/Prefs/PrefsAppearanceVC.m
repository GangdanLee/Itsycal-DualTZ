//
//  Created by Sanjay Madan on 1/11/17.
//  Copyright © 2017 mowglii.com. All rights reserved.
//

#import "PrefsAppearanceVC.h"
#import "Itsycal.h"
#import "Themer.h"
#import "Sizer.h"
#import "HighlightPicker.h"
#import "MoVFLHelper.h"
#import "IconIsConfigurableTransformer.h"

@implementation PrefsAppearanceVC
{
    NSTextField *_dateTimeFormat;
    NSTextField *_dualTZManagedHint;
    NSButton *_helpButton;
    NSButton *_hideIcon;
}

#pragma mark -
#pragma mark View lifecycle

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];

    // Convenience function for making labels.
    NSTextField* (^label)(NSString*) = ^NSTextField* (NSString *stringValue) {
        NSTextField *txt = [NSTextField labelWithString:stringValue];
        [v addSubview:txt];
        return txt;
    };

    // Convenience function for making checkboxes.
    NSButton* (^chkbx)(NSString *) = ^NSButton* (NSString *title) {
        NSButton *chkbx = [NSButton checkboxWithTitle:title target:self action:nil];
        [v addSubview:chkbx];
        return chkbx;
    };

    // Convenience function for making popups whose selected item's
    // tag is bound to the NSUserDefaults value for key.
    NSPopUpButton* (^popup)(NSArray<NSString *> *, NSArray<NSNumber *> *, NSString *) = ^NSPopUpButton* (NSArray<NSString *> *titles, NSArray<NSNumber *> *tags, NSString *key) {
        NSParameterAssert(titles.count == tags.count);
        NSPopUpButton *popup = [NSPopUpButton new];
        [popup addItemsWithTitles:titles];
        for (NSUInteger i = 0; i < tags.count; i++) {
            [popup itemAtIndex:i].tag = tags[i].integerValue;
        }
        [popup bind:@"selectedTag" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:key] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
        [v addSubview:popup];
        return popup;
    };

    // Theme popup. Each name includes "Theme" so the popup needs no label.
    NSPopUpButton *themePopup = popup(@[DualTZLoc(@"System Theme"),
                                        DualTZLoc(@"Light Theme"),
                                        DualTZLoc(@"Dark Theme")],
                                      @[@(ThemePreferenceSystem), @(ThemePreferenceLight), @(ThemePreferenceDark)],
                                      kThemePreference);

    // Size segmented control. Each segment shows "Aa" at the font
    // size it selects. All images are as tall as the large font's
    // cap height so the three "Aa"s share a baseline.
    CGFloat fontSizes[] = {FONT_SIZE_SMALL, FONT_SIZE_MEDIUM, FONT_SIZE_LARGE};
    NSArray<NSString *> *sizeNames = @[DualTZLoc(@"Small"),
                                       DualTZLoc(@"Medium"),
                                       DualTZLoc(@"Large")];
    CGFloat sizeImageHeight = ceil([NSFont systemFontOfSize:FONT_SIZE_LARGE].capHeight) + 2;
    NSMutableArray<NSImage *> *sizeImages = [NSMutableArray new];
    for (NSInteger i = 0; i < 3; i++) {
        NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:fontSizes[i]]};
        NSSize textSize = [@"Aa" sizeWithAttributes:attrs];
        NSImage *image = [NSImage imageWithSize:NSMakeSize(ceil(textSize.width), sizeImageHeight) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
            // Put the baseline 1pt above the bottom to leave room for overshoot.
            [@"Aa" drawAtPoint:NSMakePoint(0, 1 + [attrs[NSFontAttributeName] descender]) withAttributes:attrs];
            return YES;
        }];
        image.template = YES;
        image.accessibilityDescription = sizeNames[i];
        [sizeImages addObject:image];
    }
    NSSegmentedControl *sizePicker = [NSSegmentedControl segmentedControlWithImages:sizeImages trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
    for (NSInteger i = 0; i < 3; i++) [sizePicker setWidth:32 forSegment:i];
    [sizePicker.cell setAccessibilityLabel:DualTZLoc(@"Size")];
    [v addSubview:sizePicker];

    NSTextField *menubarLabel = label(DualTZLoc(@"Menu Bar"));
    NSTextField *calendarLabel = label(DualTZLoc(@"Calendar"));
    menubarLabel.font = [NSFont boldSystemFontOfSize:menubarLabel.font.pointSize-1];
    calendarLabel.font = [NSFont boldSystemFontOfSize:calendarLabel.font.pointSize-1];

    NSBox *separator0 = [NSBox new];
    NSBox *separator1 = [NSBox new];
    separator0.boxType = separator1.boxType = NSBoxSeparator;
    [v addSubview:separator0];
    [v addSubview:separator1];

    // Icon picker segmented control. The images are copies so the
    // accessibility descriptions don't change the shared images that
    // the menu bar also uses.
    NSArray<NSString *> *iconNames = @[DualTZLoc(@"Filled date"),
                                       DualTZLoc(@"Outlined date"),
                                       DualTZLoc(@"Calendar grid"),
                                       DualTZLoc(@"Itsycal face")];
    NSMutableArray<NSImage *> *iconImages = [NSMutableArray new];
    for (NSInteger i = 0; i < iconNames.count; i++) {
        NSImage *image = [[NSImage imageNamed:[NSString stringWithFormat:@"menubaricon%ld", i]] copy];
        image.accessibilityDescription = iconNames[i];
        [iconImages addObject:image];
    }
    NSSegmentedControl *iconPicker = [NSSegmentedControl segmentedControlWithImages:iconImages trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
    [iconPicker.cell setAccessibilityLabel:DualTZLoc(@"Menu bar icon")];
    [iconPicker setSelectedSegment:0]; // will be set by binding below.
    [v addSubview:iconPicker];

    // Checkboxes
    NSButton *showMonth = chkbx(DualTZLoc(@"Show month in icon"));
    NSButton *showDayOfWeek = chkbx(DualTZLoc(@"Show day of week in icon"));
    _hideIcon = chkbx(DualTZLoc(@"Hide icon"));

    // Datetime format text field
    _dateTimeFormat = [NSTextField textFieldWithString:@""];
    _dateTimeFormat.placeholderString = DualTZLoc(@"Datetime pattern");
    _dateTimeFormat.refusesFirstResponder = YES;
    _dateTimeFormat.bezelStyle = NSTextFieldRoundedBezel;
    _dateTimeFormat.usesSingleLineMode = YES;
    _dateTimeFormat.delegate = self;
    [_dateTimeFormat.cell setAccessibilityLabel:DualTZLoc(@"Menu bar date and time pattern")];
    [v addSubview:_dateTimeFormat];

    // Datetime help button
    _helpButton = [NSButton buttonWithTitle:@"" target:self action:@selector(openHelpPage:)];
    _helpButton.bezelStyle = NSBezelStyleHelpButton;
    [v addSubview:_helpButton];
    NSButton *helpButton = _helpButton;

    _dualTZManagedHint = label(DualTZLoc(@"dualtz.appearance.managed_hint"));
    _dualTZManagedHint.font = [NSFont systemFontOfSize:10.5];
    _dualTZManagedHint.textColor = [NSColor systemOrangeColor];

    // First day of week label
    NSTextField *firstDayLabel = label(DualTZLoc(@"First day of week:"));

    // First day of week popup
    NSPopUpButton *firstDayPopup = [NSPopUpButton new];
    [firstDayPopup addItemsWithTitles:@[DualTZLoc(@"Sunday"),
                                        DualTZLoc(@"Monday"),
                                        DualTZLoc(@"Tuesday"),
                                        DualTZLoc(@"Wednesday"),
                                        DualTZLoc(@"Thursday"),
                                        DualTZLoc(@"Friday"),
                                        DualTZLoc(@"Saturday")]];
    [firstDayPopup.cell setAccessibilityTitleUIElement:firstDayLabel.cell];
    [v addSubview:firstDayPopup];

    // Highlight control
    HighlightPicker *highlight = [HighlightPicker new];
    highlight.target = self;
    highlight.action = @selector(didChangeHighlight:);
    [v addSubview:highlight];

    // Calendar checkboxes
    NSButton *outlineMonth = chkbx(DualTZLoc(@"Outline current month"));
    NSButton *showEventDots = chkbx(DualTZLoc(@"Show event dots"));
    NSButton *useColoredDots = chkbx(DualTZLoc(@"Use colored dots"));
    NSButton *showWeeks = chkbx(DualTZLoc(@"Show calendar weeks"));

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @20, @"mm": @40} views:NSDictionaryOfVariableBindings(themePopup, sizePicker, menubarLabel, calendarLabel, separator0, separator1, iconPicker, showMonth, showDayOfWeek, _dateTimeFormat, helpButton, _dualTZManagedHint, _hideIcon, firstDayLabel, firstDayPopup, highlight, showWeeks, outlineMonth, showEventDots, useColoredDots)];
    [vfl :@"V:|-m-[themePopup]-m-[menubarLabel]-10-[iconPicker]-[showMonth]-[showDayOfWeek]-[_dateTimeFormat]-3-[_dualTZManagedHint]-6-[_hideIcon]-m-[calendarLabel]-10-[firstDayPopup]-m-[highlight]-m-[outlineMonth]-[showEventDots]-[useColoredDots]-[showWeeks]-m-|"];
    [vfl :@"H:|-m-[themePopup]-(>=mm)-[sizePicker]-m-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"H:|-m-[menubarLabel]-[separator0]-m-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"H:|-m-[calendarLabel]-[separator1]-m-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"H:|-m-[iconPicker]-m-|"];
    [vfl :@"H:|-m-[showMonth]-(>=m)-|"];
    [vfl :@"H:|-m-[showDayOfWeek]-(>=m)-|"];
    [vfl :@"H:|-m-[_dateTimeFormat]-[helpButton]-m-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"H:|-m-[_dualTZManagedHint]-(>=m)-|"];
    [vfl :@"H:|-m-[_hideIcon]-(>=m)-|"];
    [vfl :@"H:|-m-[firstDayLabel]-[firstDayPopup]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[highlight]-(>=m)-|"];
    [vfl :@"H:|-m-[outlineMonth]-(>=m)-|"];
    [vfl :@"H:|-m-[showEventDots]-(>=m)-|"];
    [vfl :@"H:|-mm-[useColoredDots]-(>=m)-|"];
    [vfl :@"H:|-m-[showWeeks]-(>=m)-|"];

    // Binding for size preference. SizePreference values match segment indexes.
    [sizePicker bind:@"selectedIndex" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kSizePreference] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for icon preferences
    [iconPicker bind:@"selectedIndex" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kMenuBarIconType] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSNoSelectionPlaceholderBindingOption: @0}];
    [showMonth bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowMonthInIcon] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [showDayOfWeek bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowDayOfWeekInIcon] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_hideIcon bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kHideIcon] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bind icon prefs enabled state to kHideIcon's value
    [iconPicker bind:@"enabled" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kHideIcon] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];
    [showMonth bind:@"enabled" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kHideIcon] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];
    [showDayOfWeek bind:@"enabled" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kHideIcon] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];

    // Bind icon prefs enabled state to kMenuBarIconType's value
    IconIsConfigurableTransformer *iconIsConfigurableTransformer = [IconIsConfigurableTransformer new];
    [showMonth bind:@"enabled2" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kMenuBarIconType] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSValueTransformerBindingOption: iconIsConfigurableTransformer}];
    [showDayOfWeek bind:@"enabled2" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kMenuBarIconType] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSValueTransformerBindingOption: iconIsConfigurableTransformer}];

    // Binding for datetime format
    [_dateTimeFormat bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kClockFormat] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSMultipleValuesPlaceholderBindingOption: _dateTimeFormat.placeholderString, NSNoSelectionPlaceholderBindingOption: _dateTimeFormat.placeholderString, NSNotApplicablePlaceholderBindingOption: _dateTimeFormat.placeholderString, NSNullPlaceholderBindingOption: _dateTimeFormat.placeholderString}];

    // Bindings for first day of week
    [firstDayPopup bind:@"selectedIndex" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kWeekStartDOW] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for highlight picker
    [highlight bind:@"weekStartDOW" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kWeekStartDOW] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [highlight bind:@"selectedDOWs" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kHighlightedDOWs] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for outline current month preference. The checkbox
    // shows the opposite of kDoNotDrawOutlineAroundCurrentMonth.
    [outlineMonth bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kDoNotDrawOutlineAroundCurrentMonth] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES), NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];

    // Bindings for showEventDots preference
    [showEventDots bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowEventDots] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for useColoredDots preference
    [useColoredDots bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kUseColoredDots] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [useColoredDots bind:@"enabled" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowEventDots] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for showWeeks preference
    [showWeeks bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowWeeks] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    [self updateHideIconState];
    self.view = v;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [self updateHideIconState];

    // We don't want _dateTimeFormat to be first responder.
    [self.view.window makeFirstResponder:nil];
}

- (void)openHelpPage:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://mowglii.com/itsycal/datetime.html"]];
}

- (void)updateHideIconState
{
    BOOL dualTZEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kDualTZMenuBarEnabled];
    NSString *dualTZFormat = [[NSUserDefaults standardUserDefaults] stringForKey:kDualTZMenuBarFormat];
    _dateTimeFormat.enabled = !dualTZEnabled;
    _dateTimeFormat.alphaValue = dualTZEnabled ? 0.55 : 1.0;
    _helpButton.enabled = !dualTZEnabled;
    _dualTZManagedHint.hidden = !dualTZEnabled;

    NSString *effectiveFormat = dualTZEnabled ? dualTZFormat : _dateTimeFormat.stringValue;
    if (effectiveFormat == nil || [effectiveFormat isEqualToString:@""]) {
        [_hideIcon setState:0];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kHideIcon];
        [self performSelectorOnMainThread:@selector(disableHideIcon:) withObject:nil waitUntilDone:NO];
    }
    else {
        [_hideIcon setEnabled:YES];
    }
}

- (void)disableHideIcon:(id)sender
{
    [_hideIcon setEnabled:NO];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    [self updateHideIconState];
}

- (void)didChangeHighlight:(HighlightPicker *)picker
{
    [[NSUserDefaults standardUserDefaults] setInteger:picker.selectedDOWs forKey:kHighlightedDOWs];
}

@end
