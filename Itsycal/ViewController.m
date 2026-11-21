//
//  ViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/4/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import <os/log.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ViewController.h"
#import "Itsycal.h"
#import "ItsycalWindow.h"
#import "DatePickerVC.h"
#import "SBCalendar.h"
#import "EventViewController.h"
#import "TooltipController.h"
#import "TooltipViewController.h"
#import "PrefsVC.h"
#import "PrefsGeneralVC.h"
#import "PrefsAppearanceVC.h"
#import "PrefsEventsVC.h"
#import "PrefsAboutVC.h"
#import "MoButton.h"
#import "MoPopover.h"
#import "MoVFLHelper.h"
#import "MoUtils.h"
#import "Themer.h"
#import "Sizer.h"
#import "MenuTimer.h"
#import "Itsycal-Swift.h"

// Keys observed in NSUserDefaults for preference changes. Registered in
// -fileNotifications and unregistered in -dealloc.
static NSArray<NSString *> *ObservedDefaultsKeys(void)
{
    return @[kShowEventDays, kMenuBarIconType, kShowMonthInIcon, kShowDayOfWeekInIcon,
              kShowDaysWithNoEventsInAgenda, kShowMeetingIndicator, kHideIcon,
              kBaselineOffset, kClockFormat, kWindowPosition, kShowCompletedReminders,
              kShowOverdueReminders,
              kDualTZMenuBarEnabled, kDualTZMenuBarFormat, kDualTZIconFollowsBeijing,
              kDualTZAppLanguage, kDualTZShowHeroHeader, kDualTZShowDualToday, kDualTZShowLunarSolarTerms,
              kDualTZShowChinaHolidays, kDualTZShowUSHolidays, kDualTZShowMarketingNodes,
              kDualTZShowAgendaHolidays, kDualTZShowAgendaDualTZ, kDualTZAllowBJEventCreate,
              kDualTZEnableTimeScrubber, kDualTZTimeScrubberExpanded,
              kDualTZShowThirdRefTZ, kDualTZShowDSTWarning, kDualTZShowUpcomingCountdown, kDualTZDismissedDSTDate,
              kDualTZWindowGlassStyle, kDualTZPrimaryTimeZoneID, kDualTZPrimaryCityAlias,
              kDualTZSecondaryCitiesJSON, kDualTZWorldClockOffsetRef, kDualTZWorldClockCollapsed,
              kDualTZWarnLateNight, kDualTZMenuUseAdvanced, kDualTZMenuTokensJSON];
}

// One of a day's dot colors, for -dotColorsForDate:useColor:.
@interface DotColor : NSObject
@property (nonatomic) NSColor *color;
@property (nonatomic) NSUInteger index; // first in agenda order
@property (nonatomic) NSUInteger count; // items with this color
@property (nonatomic) NSInteger rank; // of its best item
@end

@implementation DotColor
@end

@implementation ViewController
{
    EventCenter   *_ec;
    MoCalendar    *_moCal;
    // The user's calendar (autoupdating, so it follows time zone changes),
    // which can be Buddhist, Japanese, Hebrew, etc. Use it for start of
    // day, adding days, and hours/minutes/seconds, but don't read a year,
    // month or day from it: use MakeDateWithNSDate(), whose MoDates are
    // always Gregorian.
    NSCalendar    *_nsCal;
    NSStatusItem  *_statusItem;
    id             _rightClickMonitor;
    MoButton      *_btnAdd, *_btnScrubber, *_btnCal, *_btnOpt, *_btnPin;
    NSWindowController    *_prefsWC;
    AgendaViewController  *_agendaVC;
    TooltipController     *_tooltips;
    TooltipViewController *_tooltipVC;
    NSDateFormatter       *_iconDateFormatter;
    NSTimeInterval         _inactiveTime;
    NSDictionary          *_filteredEventsForDate;
    NSTimer   *_timer;
    NSString  *_clockFormat;
    BOOL       _clockUsesSeconds;
    BOOL       _clockUsesTime;
    BOOL       _shouldShowMeetingIndicator;
    NSInteger  _upcomingCountdownMinutes;
    NSRect     _screenFrame;
    NSRect     _fallbackAnchor;
    BOOL       _usesFallbackPosition;
    NSPopover *_newEventPopover;
    NSMutableArray *_notificationTokens;
    MenuTimer *_menuTimer;
    DSTWarningBannerView *_dstBannerView;
    BeijingHeroHeaderView *_heroHeaderView;
    TimeScrubberView *_scrubberView;
    NSLayoutConstraint *_dstToTopConstraint;
    NSLayoutConstraint *_heroToTopConstraint;
    NSLayoutConstraint *_heroToDstConstraint;
    NSLayoutConstraint *_calToTopConstraint;
    NSLayoutConstraint *_calToDstConstraint;
    NSLayoutConstraint *_calToHeroConstraint;
    NSLayoutConstraint *_scrubberTopConstraint;
    NSLayoutConstraint *_scrubberBtnWidthConstraint;
    NSLayoutConstraint *_agendaFromScrubberConstraint;
    NSLayoutConstraint *_agendaFromOptConstraint;
    MoDate _lastBeijingToday;
}

- (void)dealloc
{
    if (_rightClickMonitor) {
        [NSEvent removeMonitor:_rightClickMonitor];
        _rightClickMonitor = nil;
    }
    for (id token in _notificationTokens) {
        [[NSNotificationCenter defaultCenter] removeObserver:token];
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:token];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (NSString *keyPath in ObservedDefaultsKeys()) {
        [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:keyPath];
    }
}

#pragma mark -
#pragma mark View lifecycle

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Tooltips for the calendar's days and the window's buttons
    _tooltips = [TooltipController new];

    // 顶部 7 天美西夏/冬令时跳变预警条（无跳变或关闭时隐藏）
    _dstBannerView = [DualTZBridge makeDSTWarningBannerView];
    __weak typeof(self) weakSelf = self;
    _dstBannerView.onDismiss = ^{
        [weakSelf updateTopStackLayout];
    };
    [v addSubview:_dstBannerView];

    // 顶部醒目北京时间主视觉栏
    _heroHeaderView = [DualTZBridge makeHeroHeaderView];
    [v addSubview:_heroHeaderView];

    // MoCalendar
    _moCal = [MoCalendar new];
    _moCal.delegate = self;
    _moCal.target = self;
    _moCal.doubleAction = @selector(addCalendarEvent:);
    _moCal.tooltipController = _tooltips;
    [v addSubview:_moCal];
    
    // 底部 4 个原生 SF Symbols 控制按钮：+ / pin / calendar / gearshape
    MoButton* (^symbolBtn)(NSString*, NSString*, SEL, NSString*) = ^MoButton* (NSString *symbolName, NSString *key, SEL action, NSString *accDesc) {
        MoButton *btn = [MoButton new];
        [btn setTarget:self];
        [btn setAction:action];
        [btn setContentTintColor:Theme.buttonTintColor];
        NSImage *img = [[NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:accDesc]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightMedium]];
        img.template = YES;
        [btn setImage:img];
        [btn setKeyEquivalent:key];
        [btn setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
        [v addSubview:btn];
        return btn;
    };

    _btnAdd = symbolBtn(@"plus", @"n", @selector(addCalendarEvent:), @"New Event");
    _btnScrubber = [MoButton new];
    _btnScrubber.target = self;
    _btnScrubber.action = @selector(toggleScrubber:);
    NSImage *scrubIcon = [[NSImage imageWithSystemSymbolName:@"clock.arrow.2.circlepath" accessibilityDescription:@"排会换算"]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium]];
    if (!scrubIcon) {
        scrubIcon = [NSImage imageWithSystemSymbolName:@"clock" accessibilityDescription:@"排会换算"];
    }
    scrubIcon.template = YES;
    _btnScrubber.image = scrubIcon;
    _btnScrubber.contentTintColor = Theme.buttonTintColor;
    [v addSubview:_btnScrubber];

    _btnCal = symbolBtn(@"calendar", @"o", @selector(showCalendarApp:), @"Calendar");
    _btnOpt = symbolBtn(@"gearshape", @"", @selector(showOptionsMenu:), @"Options");
    _btnPin = symbolBtn(@"pin", @"p", @selector(pin:), @"Pin");
    _btnPin.keyEquivalentModifierMask = 0;
    NSImage *pinFillImg = [[NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:@"Pinned"]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightMedium]];
    pinFillImg.template = YES;
    _btnPin.alternateImage = pinFillImg;
    [_btnPin setButtonType:NSButtonTypeToggle];

    // The buttons' tooltips. Their badges show the key equivalents.
    [_tooltips addTooltipToView:_btnAdd label:^NSString *{
        return DualTZLoc(@"New Event");
    } shortcut:nil];
    [_tooltips addTooltipToView:_btnScrubber label:^NSString *{
        return DualTZLoc(@"dualtz.scrubber.tooltip");
    } shortcut:nil];
    [_tooltips addTooltipToView:_btnCal label:^NSString *{
        return DualTZLoc(@"Open Calendar");
    } shortcut:nil];
    [_tooltips addTooltipToView:_btnOpt label:^NSString *{
        return DualTZLoc(@"Options");
    } shortcut:nil];
    __weak MoButton *btnPin = _btnPin;
    [_tooltips addTooltipToView:_btnPin label:^NSString *{
        return btnPin.state == NSControlStateValueOn
            ? DualTZLoc(@"Unpin Itsycal")
            : DualTZLoc(@"Pin Itsycal");
    } shortcut:nil];

    // 可选排会时间轴换算面板（默认隐藏）
    _scrubberView = [DualTZBridge makeTimeScrubberView];
    [v addSubview:_scrubberView];

    // Agenda
    _agendaVC = [AgendaViewController new];
    _agendaVC.delegate = self;
    _agendaVC.identifier = @"AgendaVC";
    NSView *agenda = _agendaVC.view;
    [v addSubview:agenda];

    // Constraints
    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:nil views:NSDictionaryOfVariableBindings(_dstBannerView, _heroHeaderView, _moCal, _btnAdd, _btnScrubber, _btnCal, _btnOpt, _btnPin, _scrubberView, agenda)];
    [vfl :@"H:|[_dstBannerView]|"];
    [vfl :@"H:|[_heroHeaderView]|"];
    [vfl :@"H:|-2-[_moCal]-2-|"];
    [vfl :@"H:|[_scrubberView]|"];
    [vfl :@"H:|[agenda]|"];
    [vfl :@"H:|-8-[_btnAdd]-6-[_btnScrubber]-(>=0)-[_btnPin]-8-[_btnCal]-8-[_btnOpt]-8-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"V:[_moCal]-6-[_btnOpt(22)]"];
    [vfl :@"V:[agenda]-(-1)-|"];

    _scrubberBtnWidthConstraint = [_btnScrubber.widthAnchor constraintEqualToConstant:0];
    _scrubberBtnWidthConstraint.active = YES;

    _dstToTopConstraint = [_dstBannerView.topAnchor constraintEqualToAnchor:v.topAnchor];
    _heroToTopConstraint = [_heroHeaderView.topAnchor constraintEqualToAnchor:v.topAnchor];
    _heroToDstConstraint = [_heroHeaderView.topAnchor constraintEqualToAnchor:_dstBannerView.bottomAnchor constant:2];
    _calToTopConstraint = [_moCal.topAnchor constraintEqualToAnchor:v.topAnchor];
    _calToDstConstraint = [_moCal.topAnchor constraintEqualToAnchor:_dstBannerView.bottomAnchor constant:2];
    _calToHeroConstraint = [_moCal.topAnchor constraintEqualToAnchor:_heroHeaderView.bottomAnchor constant:2];

    _scrubberTopConstraint = [_scrubberView.topAnchor constraintEqualToAnchor:_btnOpt.bottomAnchor constant:4];
    _agendaFromScrubberConstraint = [agenda.topAnchor constraintEqualToAnchor:_scrubberView.bottomAnchor constant:2];
    _agendaFromOptConstraint = [agenda.topAnchor constraintEqualToAnchor:_btnOpt.bottomAnchor constant:1];

    [self updateTopStackLayout];
    [self updateScrubberState];

    self.view = v;
}

- (void)updateTopStackLayout
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [_dstBannerView refresh];
    BOOL showDST = _dstBannerView.shouldShow;
    BOOL showHero = [defaults boolForKey:kDualTZShowHeroHeader];

    // 先停用全部互斥纵向约束再按状态启用，杜绝切换瞬间约束冲突
    _dstToTopConstraint.active = NO;
    _heroToTopConstraint.active = NO;
    _heroToDstConstraint.active = NO;
    _calToTopConstraint.active = NO;
    _calToDstConstraint.active = NO;
    _calToHeroConstraint.active = NO;

    _dstBannerView.hidden = !showDST;
    _heroHeaderView.hidden = !showHero;

    if (showDST && showHero) {
        _dstToTopConstraint.active = YES;
        _heroToDstConstraint.active = YES;
        _calToHeroConstraint.active = YES;
    } else if (showDST) {
        _dstToTopConstraint.active = YES;
        _calToDstConstraint.active = YES;
    } else if (showHero) {
        _heroToTopConstraint.active = YES;
        _calToHeroConstraint.active = YES;
    } else {
        _calToTopConstraint.active = YES;
    }
}

- (void)updateScrubberState
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:kDualTZEnableTimeScrubber];
    BOOL expanded = enabled && [defaults boolForKey:kDualTZTimeScrubberExpanded];

    _btnScrubber.hidden = !enabled;
    _scrubberBtnWidthConstraint.constant = enabled ? 20 : 0;
    _btnScrubber.contentTintColor = expanded ? Theme.todayCellColor : Theme.buttonTintColor;
    _scrubberView.hidden = !expanded;

    _scrubberTopConstraint.active = NO;
    _agendaFromScrubberConstraint.active = NO;
    _agendaFromOptConstraint.active = NO;

    if (expanded) {
        _scrubberTopConstraint.active = YES;
        _agendaFromScrubberConstraint.active = YES;
        [_scrubberView setAnchorMoDate:_moCal.selectedDate];
        [_scrubberView refreshAppearanceAndRef];
    } else {
        _agendaFromOptConstraint.active = YES;
    }
}

- (void)viewDidLoad
{
    // The order of the statements is important! Subsequent statments
    // depend on previous ones.
    
    _iconDateFormatter = [NSDateFormatter new];
    _iconDateFormatter.formattingContext = NSFormattingContextStandalone;
    _iconDateFormatter.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    _inactiveTime = 0;

    // 全链路主日历锚定北京时间；美西今日仅作跨天细空心框对比标记
    _nsCal = [DualTZBridge beijingCalendar];
    _agendaVC.nsCal = _nsCal;
    
    _lastBeijingToday = [DualTZBridge beijingTodayMoDate];
    _moCal.beijingTodayDate = _lastBeijingToday;
    _moCal.todayDate = MakeDateWithNSDate([NSDate new], [NSCalendar autoupdatingCurrentCalendar]);
    _moCal.selectedDate = _lastBeijingToday;
    _moCal.showDualToday = [[NSUserDefaults standardUserDefaults] boolForKey:kDualTZShowDualToday];
    
    // Create the timer now so a timer saved before quitting resumes,
    // and before the status item, whose context menu includes it.
    _menuTimer = [MenuTimer new];

    [self createStatusItem];
    
    _ec = [[EventCenter alloc] initWithCalendar:_nsCal delegate:self];
    
    _tooltipVC = [TooltipViewController new];
    _tooltipVC.nsCal = _nsCal;

    // 首次加载即填充今日底部信息，防止系统日历未授权或延迟回调时下方短暂空白
    [self updateAgenda];
    [self updateTimer];
    
    // Now that everything else is set up, we file for notifications.
    // Some of the notification handlers rely on stuff we just set up.
    _notificationTokens = [NSMutableArray new];
    [self fileNotifications];

    [_moCal bind:@"showWeeks" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowWeeks] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"showEventDots" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowEventDots] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"useColoredDots" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kUseColoredDots] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"highlightedDOWs" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kHighlightedDOWs] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"weekStartDOW" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kWeekStartDOW] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"doNotDrawOutlineAroundCurrentMonth" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kDoNotDrawOutlineAroundCurrentMonth] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_agendaVC bind:@"showLocation" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowLocation] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // A very ugly and questionable hack. Maybe it doesn't work. It
    // shouldn't work. But I think it might. Somehow prevents(?!?)
    // defaults from temporarily changing to NULL and then reverting
    // back after the first access. The bug seems random and hard to
    // replicate so I don't know if (or why) this works. The idea is
    // a bogus first access will prevent the bug from happening when
    // the user changes defaults the first time.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"WakeUpUserDefaults"];
    [defaults synchronize];
    [defaults removeObjectForKey:@"WakeUpUserDefaults"];
    [defaults synchronize];
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL pinned = [defaults boolForKey:kPinItsycal];
    _btnPin.state = pinned ? NSControlStateValueOn : NSControlStateValueOff;
    _btnPin.contentTintColor = pinned ? Theme.todayCellColor : Theme.buttonTintColor;
    _moCal.showWeeks = [defaults boolForKey:kShowWeeks];
    _moCal.doNotDrawOutlineAroundCurrentMonth = [defaults boolForKey:kDoNotDrawOutlineAroundCurrentMonth];
    _lastBeijingToday = [DualTZBridge beijingTodayMoDate];
    _moCal.beijingTodayDate = _lastBeijingToday;
    _moCal.showDualToday = [defaults boolForKey:kDualTZShowDualToday];
    [_heroHeaderView refresh];
    [self updateTopStackLayout];
    [self updateScrubberState];

    [self.itsycalWindow makeFirstResponder:_moCal];
}

#pragma mark -
#pragma mark Keyboard & button actions

- (void)keyDown:(NSEvent *)theEvent
{
    NSString *charsIgnoringModifiers = [theEvent charactersIgnoringModifiers];
    if (charsIgnoringModifiers.length != 1) return;
    NSUInteger flags = [theEvent modifierFlags];
    BOOL noFlags = !(flags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl));
    BOOL cmdFlag = (flags & NSEventModifierFlagCommand) &&  !(flags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl));
    BOOL cmdOptFlag = (flags & NSEventModifierFlagCommand) && (flags & NSEventModifierFlagOption) &&  !(flags & (NSEventModifierFlagShift | NSEventModifierFlagControl));
    BOOL cmdShiftFlag = (flags & NSEventModifierFlagCommand) && (flags & NSEventModifierFlagShift) &&  !(flags & (NSEventModifierFlagOption | NSEventModifierFlagControl));
    unichar keyChar = [charsIgnoringModifiers characterAtIndex:0];
    
    if (keyChar == 'w' && noFlags) {
        [[NSUserDefaults standardUserDefaults] setBool:!_moCal.showWeeks forKey:kShowWeeks];
    }
    else if (keyChar == '.' && noFlags) {
        [[NSUserDefaults standardUserDefaults] setBool:!_agendaVC.showLocation forKey:kShowLocation];
    }
    else if (keyChar == ',' && cmdFlag) {
        [self showPrefs:self];
    }
    else if (keyChar == 'T' && cmdShiftFlag) {
        [self showDatePickerPopover:self];
    }
    else if (keyChar == 'r' && cmdOptFlag) {
        [_ec refresh];
    }
    else if (keyChar == 'j' && cmdFlag) {
        // Hide after joining, even when pinned, like 'esc'.
        if ([_agendaVC clickFirstActiveZoomButton]) [self hideItsycalWindow];
        else NSBeep();
    }
    else {
        [super keyDown:theEvent];
    }
}

- (void)addCalendarEvent:(id)sender
{
    // Close popover if it's already showing
    if (_newEventPopover.shown) {
        [_newEventPopover close];
        // If sender is _moCal, we are here because
        //  the user double-clicked on a date. We want
        //  to open the popover at that date. If the
        //  popover is already open, we close it and
        //  then re-open it at the double-clicked date.
        // If sender is NOT _moCal, we are here because
        //  the user clicked the New Event button. This
        //  is a toggle button, so if the popover is
        //  already open, we close it and return.
        if (sender != _moCal) return;
    }
    
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    
    if (_ec.calendarAccessGranted == NO) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = DualTZLoc(@"Calendar access was denied.");
        alert.informativeText = DualTZLoc(@"Itsycal is more useful when you allow it to add events to your calendars. You can change this setting in System Settings › Privacy & Security › Calendars.");
        [alert addButtonWithTitle:DualTZLoc(@"dualtz.events.open_privacy")];
        [alert addButtonWithTitle:DualTZLoc(@"Cancel")];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"];
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
        return;
    }
    
    // Confirm that there are calendars which can be modified
    // and hold events (not just reminder lists).
    BOOL atLeastOneModifiableCalendar = NO;
    for (id obj in [_ec sourcesAndCalendars]) {
        if ([obj isKindOfClass:[CalendarInfo class]] && 
            ((CalendarInfo *)obj).calendar.allowsContentModifications &&
            (((CalendarInfo *)obj).calendar.allowedEntityTypes & EKEntityMaskEvent)) {
            atLeastOneModifiableCalendar = YES;
            break;
        }
    }
    if (atLeastOneModifiableCalendar == NO) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = DualTZLoc(@"There are no modifiable calendars.");
        alert.informativeText = DualTZLoc(@"Itsycal cannot create a new event unless there is at least one calendar you have permission to modify.");
        [alert runModal];
        return;
    }

    if (!_newEventPopover) {
        _newEventPopover = [MoPopover new];
        _newEventPopover.animates = NO;
        _newEventPopover.delegate = self;
        // Enable coloring the full background including the arrow.
        // See EventViewController -loadView.
        _newEventPopover.hasFullSizeContent = YES;
    }
    EventViewController *eventVC = [EventViewController new];
    eventVC.ec = _ec;
    eventVC.enclosingPopover = _newEventPopover;
    eventVC.cal = _nsCal;
    eventVC.title = @"";
    eventVC.calSelectedDate = MakeNSDateWithDate(_moCal.selectedDate, _nsCal);
    eventVC.eventUndoManager = self.itsycalWindow.undoManager;
    
    _newEventPopover.contentViewController = eventVC;
    [_newEventPopover showRelativeToRect:_btnAdd.bounds ofView:_btnAdd preferredEdge:NSRectEdgeMinX];
}

- (void)showCalendarApp:(id)sender
{
    [self showCalendarAppAtDate:MakeNSDateWithDate(_moCal.selectedDate, _nsCal) dayView:NO];
}

- (void)showCalendarAppAtDate:(NSDate *)date dayView:(BOOL)dayView
{
    // Determine the default calendar app.
    // See: support.busymac.com/help/21535-busycal-url-handler
    
    UTType *icsType = [UTType typeWithFilenameExtension:@"ics"];
    CFStringRef bundleID = icsType ? LSCopyDefaultRoleHandlerForContentType((__bridge CFStringRef)icsType.identifier, kLSRolesEditor) : NULL;
    NSString *defaultCalendarAppBundleID = CFBridgingRelease(bundleID);
    
    // Use URL scheme to open BusyCal or Fantastical2 on the
    // date selected in our calendar.
    
    if ([defaultCalendarAppBundleID isEqualToString:@"com.busymac.busycal2"] ||
        [defaultCalendarAppBundleID isEqualToString:@"com.busymac.busycal3"]) {
        [self showCalendarAppWithURLScheme:@"busycalevent://date" date:date];
        return;
    }
    else if ([defaultCalendarAppBundleID isEqualToString:@"com.flexibits.fantastical2.mac"]) {
        [self showCalendarAppWithURLScheme:@"x-fantastical2://show/calendar" date:date];
        return;
    }
    
    // Use the Scripting Bridge to open Calendar.app on the
    // date selected in our calendar.
    
    SBCalendarApplication *calendarApp = [SBApplication applicationWithBundleIdentifier:@"com.apple.iCal"];
    if (calendarApp == nil) {
        NSString *message = DualTZLoc(@"The Calendar application could not be found.");
        NSAlert *alert = [NSAlert new];
        alert.messageText = message;
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }

    // HACK: Navigate Calendar.app to `date` AFTER A DELAY. Since around
    // macOS 14.5, Calendar.app seems to remember the previous date it was set
    // to and automatically reverts to it after activation. By waiting, we
    // allow Calendar.app to revert and then we navigate properly to `date`.
    [calendarApp activate]; // bring to foreground
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [calendarApp activate]; // bring to foreground
        if (dayView) [calendarApp switchViewTo:SBCalendarCALViewTypeForScriptingDayView];
        [calendarApp viewCalendarAt:date];
    });
}

- (void)showCalendarAppWithURLScheme:(NSString *)urlScheme date:(NSDate *)date
{
    // url is of the form: urlScheme/yyyy-MM-dd
    // For example: x-fantastical2://show/calendar/2011-05-22
    // The date is Gregorian whatever the user's calendar is, as MoDates are.
    MoDate moDate = MakeDateWithNSDate(date, _nsCal);
    NSString *url = [NSString stringWithFormat:@"%@/%04zd-%02zd-%02zd", urlScheme, moDate.year, moDate.month+1, moDate.day];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}

- (void)showOptionsMenu:(id)sender
{
    NSMenu *optMenu = [[NSMenu alloc] initWithTitle:@"Options Menu"];
    NSInteger i = 0;

    [optMenu insertItemWithTitle:DualTZLoc(@"About Itsycal") action:@selector(showAbout:) keyEquivalent:@"" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:DualTZLoc(@"Go to Date…") action:@selector(showDatePickerPopover:) keyEquivalent:@"T" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:DualTZLoc(@"Settings…") action:@selector(showPrefs:) keyEquivalent:@"," atIndex:i++];
    [optMenu insertItemWithTitle:DualTZLoc(@"Date & Time…") action:@selector(openDateAndTimePrefs:) keyEquivalent:@"" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:DualTZLoc(@"Help…") action:@selector(navigateToHelp:) keyEquivalent:@"" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:DualTZLoc(@"Quit Itsycal") action:@selector(terminate:) keyEquivalent:@"q" atIndex:i++];

    // Never show menu item images, whatever the system configuration.
    for (NSMenuItem *item in optMenu.itemArray) {
        item.preferredImageVisibility = NSMenuItemImageVisibilityHidden;
    }

    NSPoint pt = NSOffsetRect(_btnOpt.frame, -5, -10).origin;
    [optMenu popUpMenuPositioningItem:nil atLocation:pt inView:self.view];
}

- (void)pin:(id)sender
{
    BOOL pin = _btnPin.state == NSControlStateValueOn;
    _btnPin.contentTintColor = pin ? Theme.todayCellColor : Theme.buttonTintColor;
    [[NSUserDefaults standardUserDefaults] setBool:pin forKey:kPinItsycal];
}

- (void)toggleScrubber:(id)sender
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL nextExpanded = ![defaults boolForKey:kDualTZTimeScrubberExpanded];
    [defaults setBool:nextExpanded forKey:kDualTZTimeScrubberExpanded];
}

- (NSWindowController *)prefsWC
{
    if (!_prefsWC) {
        _prefsWC = [DualTZBridge makeSettingsWindowControllerWithEventCenter:_ec];
    }
    return _prefsWC;
}

- (void)rebuildPrefsWindowForLanguageChange
{
    if (!_prefsWC) return;
    if (!_prefsWC.window.isVisible) {
        _prefsWC = nil;
        return;
    }
    DualTZSettingsWindowController *oldVC = (DualTZSettingsWindowController *)_prefsWC;
    NSInteger prevTab = oldVC.selectedTabIndex;
    NSRect oldFrame = _prefsWC.window.frame;
    [_prefsWC close];
    _prefsWC = nil;

    DualTZSettingsWindowController *nextWC = (DualTZSettingsWindowController *)self.prefsWC;
    [nextWC selectTabAtIndex:prevTab];
    [nextWC.window setFrame:oldFrame display:YES];
    [nextWC showWindow:self];
}

- (void)showAbout:(id)sender
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [_newEventPopover close];
    DualTZSettingsWindowController *wc = (DualTZSettingsWindowController *)self.prefsWC;
    [wc showAbout];
    [wc showWindow:self];
}

- (void)showPrefs:(id)sender
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [_newEventPopover close];
    DualTZSettingsWindowController *wc = (DualTZSettingsWindowController *)self.prefsWC;
    [wc showPrefs];
    [wc showWindow:self];
}

- (void)openDateAndTimePrefs:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Date-Time-Settings.extension"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)navigateToHelp:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"https://github.com/GangdanLee/Itsycal-DualTZ#readme"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)showDatePickerPopover:(id)sender
{
    NSView *positionView = [[NSView alloc] initWithFrame:NSMakeRect(NSWidth(self.view.frame)/2 - 5, NSHeight(self.view.frame) - 70, 10, 10)];
    [self.view addSubview:positionView positioned:NSWindowBelow relativeTo:nil];

    NSPopover *datePickerPopover = [MoPopover new];

    DatePickerVC *vc = [[DatePickerVC alloc] initWithMoCal:_moCal nsCal:_nsCal];
    vc.enclosingPopover = datePickerPopover;

    datePickerPopover.contentViewController = vc;
    datePickerPopover.behavior = NSPopoverBehaviorTransient;
    // Enable coloring the full background. See DatePickerVC -loadView.
    datePickerPopover.hasFullSizeContent = YES;
    [datePickerPopover showRelativeToRect:positionView.bounds ofView:positionView preferredEdge:NSRectEdgeMinY];

    // Move the positioning view to trick the popover to hide it's arrow.
    // https://nyrra33.com/2018/08/08/a-small-trick-to-hide-nspopovers-arrow/
    positionView.frame = NSMakeRect(0, -200, 10, 10);
}

#pragma mark -
#pragma mark Menubar item

- (void)createStatusItem
{
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.target = self;
    _statusItem.button.action = @selector(statusItemClicked:);
    [_statusItem.button sendActionOn:NSEventMaskLeftMouseDown];
    [(NSButtonCell *)_statusItem.button.cell setHighlightsBy:NSNoCellMask];

    // Remember item position in menubar. (@pskowronek (Github))
    [_statusItem setAutosaveName:@"ItsycalDualTZStatusItem"];

    [self clockFormatDidChange];
    [self updateMenubarIcon];
    [self positionItsycalWindowForInitialPresentation:NO];

    // Notification for when status item view moves
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusItemMoved:) name:NSWindowDidMoveNotification object:_statusItem.button.window];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusItemMoved:) name:NSWindowDidResizeNotification object:_statusItem.button.window];

    // Right-click on status item: show context menu.
    // Use an event monitor so the system handles showing _statusItem.menu
    // with correct appearance. Clear the menu on close so left-click
    // continues to toggle the popup window.
    __weak typeof(self) weakSelf = self;
    _rightClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return event;
        if (event.window == strongSelf->_statusItem.button.window) {
            strongSelf->_statusItem.menu = [strongSelf statusItemContextMenu];
        }
        return event;
    }];
}

- (NSMenu *)statusItemContextMenu
{
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;

    for (NSMenuItem *item in [_menuTimer menuItems]) {
        [menu addItem:item];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *item = [menu addItemWithTitle:DualTZLoc(@"Settings…") action:@selector(showPrefs:) keyEquivalent:@""];
    item.target = self;
    item = [menu addItemWithTitle:DualTZLoc(@"Date & Time…") action:@selector(openDateAndTimePrefs:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    item = [menu addItemWithTitle:DualTZLoc(@"Quit Itsycal") action:@selector(terminate:) keyEquivalent:@""];
    item.target = NSApp;

    // Never show menu item images, whatever the system configuration.
    for (NSMenuItem *item in menu.itemArray) {
        item.preferredImageVisibility = NSMenuItemImageVisibilityHidden;
    }

    return menu;
}

- (void)updateStatusItemFont
{
    static NSFontDescriptor *origFontDesc = nil;
    static NSFontDescriptor *monoFontDesc = nil;
    // Use monospaced font if user sets custom clock format that
    // uses seconds so the status item doesn't move distractingly
    // every second. It still moves each minute if showing time.
    // We modify the default font with a font descriptor instead
    // of using +monospacedDigitSystemFontOfSize:weight: because
    // we get slightly darker looking ':' characters this way.
    if (_clockUsesSeconds) {
        if (!monoFontDesc) {
            origFontDesc = [_statusItem.button.font fontDescriptor];
            monoFontDesc = [origFontDesc fontDescriptorByAddingAttributes:@{NSFontFeatureSettingsAttribute: @[@{NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType), NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}]}];
        }
        _statusItem.button.font = [NSFont fontWithDescriptor:monoFontDesc size:0];
    }
    else if (origFontDesc) {
        _statusItem.button.font = [NSFont fontWithDescriptor:origFontDesc size:0];
    }
}

- (void)removeStatusItem
{
    if (_rightClickMonitor) {
        [NSEvent removeMonitor:_rightClickMonitor];
        _rightClickMonitor = nil;
    }
    if (_statusItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidMoveNotification object:_statusItem.button.window];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResizeNotification object:_statusItem.button.window];
        // Let 10.12+ remember item position and remove item when app is terminated.
        // If we remove item ourselves, autosavename is deleted from user defaults.
        // (@pskowronek (Github))
        // DO NOT do this:
        //   [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
        //   _statusItem = nil;
    }
}

- (NSString *)iconText
{
    NSString *iconText;
    BOOL followBeijing = [[NSUserDefaults standardUserDefaults] boolForKey:kDualTZIconFollowsBeijing];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kShowMonthInIcon] || [[NSUserDefaults standardUserDefaults] boolForKey:kShowDayOfWeekInIcon]) {
        BOOL zh = [DualTZBridge isChineseLanguage];
        NSString *languageCode = followBeijing ? (zh ? @"zh" : @"en") : NSLocale.currentLocale.languageCode;
        NSString *countryCode = followBeijing ? (zh ? @"CN" : @"US") : NSLocale.currentLocale.countryCode;
        NSString *languageAndCountry = (languageCode && countryCode)
            ? [NSString stringWithFormat:@"%@_%@", languageCode, countryCode]
            : (languageCode ?: @"en");
        NSString *localeID = [languageAndCountry stringByAppendingString:@"@calendar=gregorian"];
        NSLocale *localeWithoutCalendar = [NSLocale localeWithLocaleIdentifier:localeID];
        NSMutableString *template = @"d".mutableCopy;
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kShowMonthInIcon]) {
            [template appendString:@"MMM"];
        }
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kShowDayOfWeekInIcon]) {
            [template appendString:@"EEE"];
        }
        _iconDateFormatter.locale = localeWithoutCalendar;
        _iconDateFormatter.timeZone = followBeijing
            ? [DualTZBridge beijingCalendar].timeZone
            : [NSTimeZone localTimeZone];
        [_iconDateFormatter setDateFormat:[NSDateFormatter dateFormatFromTemplate:template options:0 locale:localeWithoutCalendar]];
        iconText = [_iconDateFormatter stringFromDate:[NSDate new]];
    } else {
        MoDate iconDate = followBeijing ? [DualTZBridge beijingTodayMoDate] : _moCal.todayDate;
        iconText = [NSString stringWithFormat:@"%zd", iconDate.day];
    }
    
    if (iconText == nil) {
        iconText = @"!!";
    }
    return iconText;
}

- (void)updateMenubarIcon
{
    NSString *accessibilityTitle = @"Itsycal";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hideIcon = [defaults boolForKey:kHideIcon];
    NSString *countdownSuffix = [self upcomingMeetingCountdownSuffix];
    BOOL hasTitleText = (_clockFormat != nil && ![_clockFormat isEqualToString:@""]) || countdownSuffix.length > 0;
    if (hideIcon) {
        if ([defaults boolForKey:kShowMeetingIndicator] && _shouldShowMeetingIndicator) {
            NSImage *meetIndicator = [NSImage imageNamed:@"meetSolid"];
            meetIndicator.template = YES;
            _statusItem.button.image = meetIndicator;
            _statusItem.button.imagePosition = hasTitleText ? NSImageLeft : NSImageOnly;
        }
        else {
            _statusItem.button.image = nil;
            _statusItem.button.imagePosition = NSNoImage;
        }
    }
    else {
        NSString *iconText = [self iconText];
        accessibilityTitle = [accessibilityTitle stringByAppendingFormat:@", %@", iconText];
        _statusItem.button.image = [self iconImageForText:iconText];
        _statusItem.button.imagePosition = hasTitleText ? NSImageLeft : NSImageOnly;
    }
    if (hasTitleText) {
        CGFloat baselineOffset = [defaults floatForKey:kBaselineOffset];
        baselineOffset = MIN(2.0, MAX(-2.0, baselineOffset));
        NSString *buttonText = @"";
        if (_clockFormat && ![_clockFormat isEqualToString:@""]) {
            if ([defaults boolForKey:kDualTZMenuBarEnabled]) {
                buttonText = [DualTZBridge formatMenubarClock:_clockFormat at:[NSDate new]];
            } else {
                _iconDateFormatter.locale = [DualTZBridge effectiveLocale];
                _iconDateFormatter.timeZone = [NSTimeZone localTimeZone];
                [_iconDateFormatter setDateFormat:_clockFormat];
                buttonText = [_iconDateFormatter stringFromDate:[NSDate new]];
            }
        }
        if (countdownSuffix.length > 0) {
            buttonText = buttonText.length > 0 ? [buttonText stringByAppendingString:countdownSuffix] : countdownSuffix;
        }
        accessibilityTitle = [accessibilityTitle stringByAppendingFormat:@", %@", buttonText];
        if (!hideIcon && buttonText.length > 0) {
            buttonText = [@" " stringByAppendingString:buttonText];
        }
        _statusItem.button.attributedTitle = [
            [NSAttributedString alloc] initWithString:buttonText attributes:@{
            NSBaselineOffsetAttributeName: @(baselineOffset)}];
    } else {
        _statusItem.button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
        _statusItem.button.title = @"";
    }
    _statusItem.button.accessibilityTitle = accessibilityTitle;
    [self adjustStatusItemWidthIfNecessary];
}

- (void)adjustStatusItemWidthIfNecessary
{
    // Set a fixed width for _statusItem if it uses a clock format
    // but doesn't show seconds. This prevents the _statusItem from
    // slightly shifting in the menubar when time changes due to the
    // different widths of digits in the proportional font.
    static NSStatusBarButton *dummyButton = nil;
    if (_clockFormat && !_clockUsesSeconds) {
        if (!dummyButton) {
            NSFontDescriptor *monoFontDesc = [[_statusItem.button.font fontDescriptor] fontDescriptorByAddingAttributes:@{NSFontFeatureSettingsAttribute: @[@{NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType), NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}]}];
            dummyButton = [NSStatusBarButton new];
            dummyButton.font = [NSFont fontWithDescriptor:monoFontDesc size:0];
        }
        // Same logic as -updateMenubarIcon to set up dummyButton
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:kHideIcon]) {
            if ([defaults boolForKey:kShowMeetingIndicator] && _shouldShowMeetingIndicator) {
                dummyButton.image = [NSImage imageNamed:@"meetSolid"];
                dummyButton.imagePosition = NSImageLeft;
            }
            else {
                dummyButton.image = nil;
                dummyButton.imagePosition = NSNoImage;
            }
        }
        else {
            dummyButton.image = _statusItem.button.image;
            dummyButton.imagePosition = _clockFormat ? NSImageLeft : NSImageOnly;
        }
        dummyButton.title = _statusItem.button.title;
        [dummyButton sizeToFit];
        _statusItem.length = NSWidth(dummyButton.frame) - 8;
        //os_log(OS_LOG_DEFAULT, "[%@] %@ --> %.0f, %.0f", [self iconText], _statusItem.button.title,
        //      _statusItem.button.frame.size.width, _statusItem.button.image.size.width);
    }
    else {
        _statusItem.length = NSVariableStatusItemLength;
        //os_log(OS_LOG_DEFAULT, "VARIABLE LENGTH ITEM");
    }
}

- (NSImage *)iconImageForText:(NSString *)text
{
    if (text == nil) text = @"!";

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSInteger menuBarIconType = [defaults integerForKey:kMenuBarIconType];
    if (menuBarIconType == 2) {
        return [NSImage imageNamed:@"menubaricon2"];
    }
    if (menuBarIconType == 3) {
        return [NSImage imageNamed:@"menubaricon3"];
    }

    // Does user want outline icon or solid icon?
    BOOL outline = menuBarIconType == 1;

    // Should we show the virtual meeting indicator?
    BOOL meeting = [defaults boolForKey:kShowMeetingIndicator] && _shouldShowMeetingIndicator;

    // Return cached icon if one is available.
    NSString *iconName = [NSString stringWithFormat:@"%@ %@ %@", text, outline ? @"outline" : @"solid", meeting ? @"meeting" : @"nomeeting"];
    NSImage *iconImage = [NSImage imageNamed:iconName];
    if (iconImage != nil) return iconImage;

    // Measure text width
    CGFloat fontSize = 11.5;
    NSFont *font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightBold];
    CGRect textRect = [[[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: font}] boundingRectWithSize:CGSizeMake(999, 999) options:0 context:nil];

    // Icon width is at least 17 pts with 4 pt inside margins.
    CGFloat meetingWidth = meeting ? 18 : 0;
    CGFloat width = MAX(4 + meetingWidth + ceilf(NSWidth(textRect)) + 4, 17);
    CGFloat height = 16;
    iconImage = [NSImage imageWithSize:NSMakeSize(width, height) flipped:NO drawingHandler:^BOOL (NSRect rect) {
        
        CGFloat meetingOffset = meeting ? 9 : 0;
        
        // Draw meeting indicator if necessary;
        if (meeting) {
            NSString *imageName = outline ? @"meetSolid" : @"meetOutline";
            [[NSImage imageNamed:imageName] drawAtPoint:NSMakePoint(3, 0) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        }

        // Draw text.
        if (outline) CGContextSetShouldSmoothFonts(NSGraphicsContext.currentContext.CGContext, false);
        NSFontWeight fontWeight = outline ? NSFontWeightSemibold : NSFontWeightBold;
        NSMutableParagraphStyle *pstyle = [NSMutableParagraphStyle new];
        pstyle.alignment = NSTextAlignmentCenter;
        [text drawInRect:NSOffsetRect(rect, meetingOffset, -1) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:fontWeight], NSParagraphStyleAttributeName: pstyle}];
        
        // Draw rounded rect.
        [NSColor.blackColor set];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationXOR];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4] fill];
        if (outline) [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1, 1) xRadius:3 yRadius:3] fill];
        [NSGraphicsContext restoreGraphicsState];

        return YES;
    }];
    [iconImage setTemplate:YES];
    [iconImage setName:iconName];
    return iconImage;
}

- (void)positionItsycalWindowForInitialPresentation:(BOOL)initialPresentation
{
    NSRect statusItemFrame = [_statusItem.button.window convertRectToScreen:_statusItem.button.frame];

    // Hack alert:
    // MacOS 11 does not report the correct frame for _statusItem.button
    // if its length is adjusted (see -adjustStatusItemWidthIfNecessary).
    // As a result, this method positions the window *uncentered* below
    // the status item. Adjust the frame with a value empirically
    // determined to make the window appear centered.
    if (_statusItem.length != NSVariableStatusItemLength) {
        statusItemFrame.size.width += 15;
    }
    
    // Hack alert:
    // Which screen is the status item on? I'd like to just use
    // _statusItem.button.window.screen, but that property is nil
    // when the user is working with a full screen app: the menu
    // bar is hidden and so the status item is offscreen.
    // Alternatively, I'd like to use [NSScreen mainscreen], but
    // that method seems to give the wrong answer when the user
    // is working on an external monitor with a full screen app.
    // So... I iterate over all the screens and see which one
    // contains the statusItem's origin. I adjust the origin
    // down a bit to account for the case where the menu bar is
    // hidden (as it is when an app is in fullscreen mode) as
    // the system *currently* places the status item just above
    // its screen. This isn't documented behavior and so might
    // not work in the future.
    NSScreen *statusItemScreen = nil;
    NSPoint testPoint = statusItemFrame.origin;
    testPoint.y -= 100;
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(testPoint, screen.frame)) {
            statusItemScreen = screen;
            break;
        }
    }

    // A status item moved fully offscreen by a menu bar manager is not a
    // useful anchor. In that case, keep Itsycal onscreen at the top right
    // of the screen. The user can also choose to always show Itsycal there.
    BOOL useFallbackPosition = statusItemScreen == nil
        || [[NSUserDefaults standardUserDefaults] integerForKey:kWindowPosition] == WindowPositionTopRightOfScreen;

    // When first showing Itsycal, don't anchor to an item that isn't
    // visible, such as one covered by app menus or hidden along with a
    // fullscreen app's menu bar. The exception is an auto-hiding desktop
    // menu bar: it moves the item just above its screen, where it reports
    // itself as not visible, but its x position is still a good anchor.
    // Skip this check for an already open window, since the menu bar can
    // auto-hide while Itsycal is open.
    if (initialPresentation && !useFallbackPosition
        && NSMinY(statusItemFrame) < NSMaxY(statusItemScreen.frame)) {
        BOOL itemIsVisible = !!(_statusItem.button.window.occlusionState & NSWindowOcclusionStateVisible);
        useFallbackPosition = !itemIsVisible;
    }

    // Once Itsycal is shown in the fallback position, keep it there while
    // it remains open. Otherwise it would jump under the status item when
    // the menu bar is revealed or the item moves. Recompute the position
    // only if the screen Itsycal is on has gone away or changed size.
    NSScreen *fallbackScreen = nil;
    if (!initialPresentation && _usesFallbackPosition) {
        for (NSScreen *screen in [NSScreen screens]) {
            if (NSEqualRects(screen.frame, _screenFrame)) {
                fallbackScreen = screen;
                break;
            }
        }
    }

    if (fallbackScreen != nil) {
        statusItemScreen = fallbackScreen;
        statusItemFrame = _fallbackAnchor;
    }
    else if (useFallbackPosition) {
        // A hidden status item can still identify its display. Use the
        // main screen only when the item is fully offscreen.
        if (statusItemScreen == nil) {
            statusItemScreen = [NSScreen mainScreen];
        }
        // Anchor to the top right of the screen, below the menu bar so
        // that the menu bar doesn't cover Itsycal.
        statusItemFrame = NSMakeRect(NSMaxX(statusItemScreen.frame),
                                     NSMaxY(statusItemScreen.visibleFrame), 0, 0);
        _fallbackAnchor = statusItemFrame;
    }
    _usesFallbackPosition = fallbackScreen != nil || useFallbackPosition;
    _screenFrame = statusItemScreen.frame;
    CGFloat screenMaxX = NSMaxX(statusItemScreen.frame);

    // Constrain the menu item's frame to be no higher than the top
    // of the screen. For some reason, when an app is in fullscreen
    // mode sometimes the menu item frame is reported to be *above*
    // the top of the screen. The result is that the calendar is
    // shown clipped at the top. Prevent that by constraining the
    // top of the menu item to be at most the top of the screen.
    statusItemFrame.origin.y = MIN(statusItemFrame.origin.y, NSMaxY(statusItemScreen.frame));
    
    // So that agenda height can adjust to fit screen if needed.
    [_agendaVC.view setNeedsLayout:YES];

    [self.itsycalWindow positionRelativeToRect:statusItemFrame screenMaxX:screenMaxX];
}

- (void)statusItemMoved:(NSNotification *)note
{
    // Reposition itsycalWindow so that it remains
    // centered under _statusItemView.
    //
    // We do the repositioning after a slight delay to account
    // for the following scenario:
    //  - The user has more than one screen.
    //  - Itsycal is visible on one of them.
    //  - The user clicks the menu item on the other screen.
    //
    // In this scenario, this method will be called because the
    // user's click "moved" the status item window from one screen
    // to another. If we repositioned the window immediately, it
    // would be placed on the active screen and the logic in
    // -statusItemClicked: would not be able to know that the click
    // occurred in a different screen from the one where Itsycal
    // was showing. The result would be Itsycal flashing in the
    // new screen (because of this method's repositioning) and then
    // hiding because that's the logic that would execute in the
    // -statusItemClicked: method. The delay let's -menuItemClicked:
    // handle this scenario first.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self positionItsycalWindowForInitialPresentation:NO];
    });
}

- (void)statusItemClicked:(id)sender
{
    // If there are multiple screens and Itsycal is showing
    // on one and the user clicks the menu item on another,
    // instead of a regular toggle, we want Itsycal to hide
    // from it's old screen and show in the new one.
    // To distinguish screens, we used to use the screen address,
    // but with macOS Big Sur, that is not reliable. Instead,
    // we now use the screen's frame.
    if (!NSEqualRects(self.itsycalWindow.screen.frame, NSScreen.mainScreen.frame)) {
        if ([self.itsycalWindow occlusionState] & NSWindowOcclusionStateVisible) {
            // The slight delay before showing the window in the new
            // position is to allow -windowDidResignKey: to execute
            // first so that it doesn't hide the window we are
            // trying to show.
            [self.itsycalWindow orderOut:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self showItsycalWindow];
            });
            return;
        }
    }
    if ([self.itsycalWindow occlusionState] & NSWindowOcclusionStateVisible) {
        [self hideItsycalWindow];
    }
    else {
        [self showItsycalWindow];
    }
}

#pragma mark -
#pragma mark NSMenu Delegate

- (void)menuDidClose:(NSMenu *)menu
{
    // The status item shows a menu on right-click. Clear the menu on close
    // so that left-click continues to toggle the Itsycal window.
    // See -createStatusItem for more info.
    if (_statusItem.menu == menu) {
        _statusItem.menu = nil;
        [_menuTimer menuDidClose];
    }
}

#pragma mark -
#pragma mark Window management

- (ItsycalWindow *)itsycalWindow
{
    return (ItsycalWindow *)self.view.window;
}

- (void)showItsycalWindow
{
    [[NSApplication sharedApplication] unhideWithoutActivation];
    [self positionItsycalWindowForInitialPresentation:YES];
    [_agendaVC scrollToTop];
    [self.itsycalWindow makeKeyAndOrderFront:self];
    [self.itsycalWindow makeFirstResponder:_moCal];
    _inactiveTime = 0;
}

- (void)hideItsycalWindow
{
    [_tooltips hideImmediately];
    [self.itsycalWindow orderOut:self];
    [_newEventPopover close];
    _inactiveTime = MonotonicClockTime();
}

- (void)cancel:(id)sender
{
    // User pressed 'esc'.
    [self hideItsycalWindow];
}

- (void)windowDidResize:(NSNotification *)notification
{
    [self positionItsycalWindowForInitialPresentation:NO];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    if (_btnPin.state == NSControlStateValueOff) {
        [self hideItsycalWindow];
    }
}

- (void)popoverDidClose:(NSNotification *)notification
{
    if (notification.object == _newEventPopover) {
        _newEventPopover = nil;
    }
}

- (void)keyboardShortcutActivated
{
    // The user hit the keyboard shortcut. This is the same
    // as if the user had clicked the menubar icon.
    [self statusItemClicked:self];
}

- (void)dateURLReceived:(NSDate *)showDate
{
    // We received a URL asking us to show a specific date.
    MoDate selectedDate = MakeDateWithNSDate(showDate, _nsCal);
    _moCal.selectedDate = selectedDate;
    
    // Only "click" the status item if the itsycal window isn't already visible.
    // Otherwise, it would just close.
    if (!([self.itsycalWindow occlusionState] & NSWindowOcclusionStateVisible)) {
        [self statusItemClicked:self];
    }

}

#pragma mark -
#pragma mark AgendaDelegate

- (void)agendaHoveredOverRow:(NSInteger)row
{
    if (row == -1) {
        [_moCal unhighlightCells];
    }
    else {
        EventInfo *info = _agendaVC.events[row];
        if (info.isVirtualItem) {
            MoDate vDate = MakeDateWithNSDate(info.date, _nsCal);
            [_moCal highlightCellsFromDate:vDate toDate:vDate withColor:(info.virtualColor ?: Theme.todayCellColor)];
            return;
        }
        if (info.reminder) {
            MoDate dueDate = MakeDateWithNSDate(info.dueDate, _nsCal);
            [_moCal highlightCellsFromDate:dueDate toDate:dueDate withColor:info.reminder.calendar.color];
            return;
        }
        if (info.event.isAllDay) {
            NSCalendar *localCal = [NSCalendar autoupdatingCurrentCalendar];
            MoDate startDate = MakeDateWithNSDate(info.event.startDate, localCal);
            MoDate endDate   = MakeDateWithNSDate(info.event.endDate,   localCal);
            if ([info.event.endDate compare:[localCal startOfDayForDate:info.event.endDate]] == NSOrderedSame &&
                CompareDates(endDate, startDate) > 0) {
                endDate = AddDaysToDate(-1, endDate);
            }
            [_moCal highlightCellsFromDate:startDate toDate:endDate withColor:info.event.calendar.color];
            return;
        }
        MoDate startDate = MakeDateWithNSDate(info.event.startDate, _nsCal);
        MoDate endDate   = MakeDateWithNSDate(info.event.endDate,   _nsCal);
        // Fixup for endDates that are at midnight in Beijing calendar
        if ([info.event.endDate compare:[_nsCal startOfDayForDate:info.event.endDate]] == NSOrderedSame &&
            CompareDates(endDate, startDate) > 0) {
            endDate = AddDaysToDate(-1, endDate);
        }
        [_moCal highlightCellsFromDate:startDate toDate:endDate withColor:info.event.calendar.color];
    }
}

- (void)agendaWantsToDeleteEvent:(EKEvent *)event
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    
    // Make a string showing the event title and duration.
    NSString *title = event.title == nil ? @"" : event.title;
    NSTimeZone *durTZ = event.isAllDay ? [NSTimeZone localTimeZone] : _nsCal.timeZone;
    NSString *duration = DateRangeStringInTimeZone(event.startDate, event.endDate, event.isAllDay, durTZ);
    NSString *eventString = [NSString stringWithFormat:@"%@\n%@", title, duration];

    BOOL eventRepeats = event.hasRecurrenceRules;
    
    // Ask the user to confirm they want to delete this event (or future events).
    NSAlert *alert = [NSAlert new];
    if (eventRepeats == YES) {
        alert.messageText = DualTZLoc(@"You're deleting an event.");
        alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", eventString, DualTZLoc(@"Do you want to delete this and all future occurrences of this event, or only the selected occurrence?")];
        [alert addButtonWithTitle:DualTZLoc(@"Delete Only This Event")];
        [alert addButtonWithTitle:DualTZLoc(@"Delete All Future Events")];
    }
    else {
        alert.messageText = DualTZLoc(@"Are you sure you want to delete this event?");
        alert.informativeText = eventString;
        [alert addButtonWithTitle:DualTZLoc(@"Delete This Event")];
    }
    [alert addButtonWithTitle:DualTZLoc(@"Cancel")];
    NSModalResponse response = [alert runModal];
    
    // Return if the user chose 'Cancel'.
    if ((eventRepeats == YES && response == NSAlertThirdButtonReturn) ||
        (eventRepeats == NO && response == NSAlertSecondButtonReturn)) {
        return;
    }
    
    // Delete this event (or future events).
    NSError *error = NULL;
    EKSpan span = (eventRepeats && response == NSAlertSecondButtonReturn) ? EKSpanFutureEvents : EKSpanThisEvent;
    BOOL result = [_ec removeEvent:event span:span error:&error];
    if (result == NO && error != nil) {
        [[NSAlert alertWithError:error] runModal];
    }
}

- (void)agendaWantsToSetReminder:(EKReminder *)reminder completed:(BOOL)completed
{
    // Check off or uncheck. Undo is registered with the window's
    // undo manager, like new events, so ⌘Z works.
    NSError *error = nil;
    BOOL result = [_ec setReminder:reminder completed:completed undoManager:self.itsycalWindow.undoManager error:&error];
    if (result == NO && error != nil) {
        [[NSAlert alertWithError:error] runModal];
    }
}

- (void)agendaShowCalendarAppAtDate:(NSDate *)date
{
    [self showCalendarAppAtDate:date dayView:YES];
}

- (CGFloat)agendaMaxPossibleHeight
{
    CGFloat extraH = 0;
    if (!_heroHeaderView.isHidden) extraH += NSHeight(_heroHeaderView.frame) + 2;
    if (!_dstBannerView.isHidden) extraH += NSHeight(_dstBannerView.frame) + 2;
    if (!_scrubberView.isHidden) extraH += NSHeight(_scrubberView.frame) + 4;
    return MAX(80, NSHeight(_screenFrame) - NSHeight(_moCal.frame) - 140 - extraH);
}

#pragma mark -
#pragma mark MoCalendarDelegate

- (void)calendarUpdated:(MoCalendar *)cal
{
    // Attempt to reload cached events. If this works,
    // the display will update fast. Then fetch.
    [_moCal reloadData];
    [_ec fetchEvents];
}

- (void)calendarSelectionChanged:(MoCalendar *)cal
{
    [self updateAgenda];
    if (!_scrubberView.isHidden) {
        [_scrubberView setAnchorMoDate:cal.selectedDate];
    }
}

- (id<TooltipContent>)tooltipContentForDate:(MoDate)date
{
    NSArray *events = [self eventsForDate:date];
    NSString *summary = [DualTZBridge hasSpecialDayDetailForDate:date]
        ? [DualTZBridge tooltipHolidaySummaryForDate:date]
        : nil;
    if (events.count == 0 && summary.length == 0) return nil;
    return [_tooltipVC tooltipContentForEvents:events headerText:summary];
}

- (NSArray<NSColor *> *)dotColorsForDate:(MoDate)date useColor:(BOOL)useColor
{
    NSArray<EventInfo *> *events = [self eventsForDate:date];
    if (!events || events.count == 0) return nil;
    if (!useColor) return @[];

    // A dot for each color, up to 3; calendars with the same color share
    // a dot. When there are more than 3 colors, a color ranks by its best
    // item: first an open item in a writable calendar, so read-only ones
    // (holidays, birthdays, other subscriptions) can't crowd out the
    // user's own; then an open item in a read-only calendar or a later
    // occurrence of a repeating reminder; last a completed reminder.
    // Then colors with more items, then the earlier in the agenda.
    NSMutableArray<DotColor *> *dots = [NSMutableArray new]; // agenda order
    NSMutableDictionary<NSColor *, DotColor *> *dotsByColor = [NSMutableDictionary new];
    for (EventInfo *info in events) {
        EKCalendar *calendar = info.item.calendar;
        NSColor *color = calendar.color;
        if (color == nil) continue;
        NSInteger rank = info.reminder.isCompleted ? 0
            : (calendar.allowsContentModifications && !info.isFutureOccurrence) ? 2 : 1;
        DotColor *dot = dotsByColor[color];
        if (dot == nil) {
            dot = [DotColor new];
            dot.color = color;
            dot.index = dots.count;
            dot.rank = rank;
            [dots addObject:dot];
            dotsByColor[color] = dot;
        }
        dot.count++;
        dot.rank = MAX(dot.rank, rank);
    }
    if (dots.count == 0) return @[]; // a plain dot

    // Pick the 3 that rank highest, then draw them in agenda order.
    if (dots.count > 3) {
        [dots sortUsingComparator:^NSComparisonResult(DotColor *d1, DotColor *d2) {
            if (d1.rank  != d2.rank)  return d1.rank  > d2.rank  ? NSOrderedAscending : NSOrderedDescending;
            if (d1.count != d2.count) return d1.count > d2.count ? NSOrderedAscending : NSOrderedDescending;
            return d1.index < d2.index ? NSOrderedAscending : NSOrderedDescending;
        }];
        [dots removeObjectsInRange:NSMakeRange(3, dots.count - 3)];
        [dots sortUsingComparator:^NSComparisonResult(DotColor *d1, DotColor *d2) {
            return d1.index < d2.index ? NSOrderedAscending : NSOrderedDescending;
        }];
    }
    NSMutableArray<NSColor *> *dotColors = [NSMutableArray new];
    for (DotColor *dot in dots) [dotColors addObject:dot.color];
    return dotColors;
}

#pragma mark - Events

- (NSArray *)eventsForDate:(MoDate)date
{
    NSDate *nsDate = MakeNSDateWithDate(date, _nsCal);
    return _filteredEventsForDate[nsDate];
}

- (NSArray<EventInfo *> *)virtualEventInfosForMoDate:(MoDate)date nsDate:(NSDate *)nsDate
{
    NSArray<DualTZVirtualAgendaItem *> *items = [DualTZBridge virtualAgendaItemsForDate:date];
    if (items.count == 0) return @[];
    NSMutableArray<EventInfo *> *result = [NSMutableArray arrayWithCapacity:items.count];
    for (DualTZVirtualAgendaItem *item in items) {
        EventInfo *info = [EventInfo new];
        info.date = nsDate;
        info.isAllDay = YES;
        info.isVirtualItem = YES;
        info.virtualTitle = item.title;
        info.virtualTag = item.tagText;
        info.virtualSubtitle = item.subtitle;
        info.virtualColor = item.dotColor;
        [result addObject:info];
    }
    return result;
}

- (NSArray *)datesAndEventsForDate:(MoDate)date days:(NSInteger)days
{
    if (days <= 0) return @[];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL showAgendaHolidays = [defaults boolForKey:kDualTZShowAgendaHolidays];
    BOOL showEmptyDays = [defaults boolForKey:kShowDaysWithNoEventsInAgenda];
    BOOL calDenied = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent] == EKAuthorizationStatusDenied;

    NSMutableArray *datesAndEvents = [NSMutableArray new];
    for (NSInteger offset = 0; offset < days; offset++) {
        MoDate curDate = AddDaysToDate(offset, date);
        NSDate *nsDate = MakeNSDateWithDate(curDate, _nsCal);
        [nsDate setIsSelectedAnchorDate:(offset == 0)];

        NSArray *realEvents = _filteredEventsForDate[nsDate] ?: @[];
        NSArray *virtualEvents = showAgendaHolidays ? [self virtualEventInfosForMoDate:curDate nsDate:nsDate] : @[];
        NSArray *combined = [virtualEvents arrayByAddingObjectsFromArray:realEvents];

        if (combined.count > 0) {
            [nsDate setHasNoEvents:NO];
            [datesAndEvents addObject:nsDate];
            [datesAndEvents addObjectsFromArray:combined];
        } else if ((offset == 0 && showAgendaHolidays) || showEmptyDays) {
            // 为空日构建占位行，选中锚点日附带温和中文无日程提示
            [nsDate setHasNoEvents:YES];
            [datesAndEvents addObject:nsDate];
            EventInfo *noEvents = [EventInfo new];
            noEvents.date = nsDate;
            if (showAgendaHolidays) {
                noEvents.emptyPlaceholderText = calDenied
                    ? DualTZLoc(@"dualtz.agenda.empty_denied")
                    : DualTZLoc(@"dualtz.agenda.empty");
            }
            [datesAndEvents addObject:noEvents];
        }
    }
    return datesAndEvents;
}

#pragma mark -
#pragma mark EventCenterDelegate

- (void)eventCenterEventsChanged
{
    //os_log(OS_LOG_DEFAULT, "%s", __FUNCTION__);
    _filteredEventsForDate = [_ec filteredEventsForDate];
    [_moCal reloadData];
    // Only the data changed. While the user is looking, keep their place.
    // (The agenda scrolls to the top when the window opens.)
    [self updateAgendaKeepingScrollPosition:self.itsycalWindow.isVisible];
}

- (MoDate)fetchStartDate
{
    return _moCal.firstDate;
}

- (MoDate)fetchEndDate
{
    // The end date is exclusive. Cover the calendar's last date and an
    // agenda that starts on it, which ends `days` days later.
    return AddDaysToDate(MAX([self daysToShowInAgenda], 1), _moCal.lastDate);
}

#pragma mark -
#pragma mark Agenda

- (NSInteger)daysToShowInAgenda
{
    NSInteger days = [[NSUserDefaults standardUserDefaults] integerForKey:kShowEventDays];
    days = MIN(MAX(days, 0), 9); // days is in range 0..9
    // days == 8 really means 14; 9 really means 31
    if (days == 8) days = 14; else if (days == 9) days = 31;
    return days;
}

- (void)updateAgenda
{
    [self updateAgendaKeepingScrollPosition:NO];
}

// Keep the scroll position when only the data changed, so the user
// doesn't lose their place, e.g. checking off reminders in a long list.
// Otherwise (a new date, a setting) start from the top.
- (void)updateAgendaKeepingScrollPosition:(BOOL)keepScrollPosition
{
    NSInteger days = [self daysToShowInAgenda];
    NSArray *datesAndEvents = [self datesAndEventsForDate:_moCal.selectedDate days:days];
    _agendaVC.events = [[self overdueRowsForAgendaDays:days] arrayByAddingObjectsFromArray:datesAndEvents];
    if (keepScrollPosition) {
        [_agendaVC reloadDataKeepingScrollPosition];
    }
    else {
        [_agendaVC reloadData];
    }
    [self showMeetingIndicatorIfNecessary];
}

// The Overdue section at the top of the agenda: a heading with the
// number of reminders due before today and, if the user expanded it,
// those reminders, most recent day first. It's shown only for today
// (it's about now) and if the agenda shows any days. It starts
// collapsed, and remembers whether it's expanded.
- (NSArray *)overdueRowsForAgendaDays:(NSInteger)days
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (days == 0 ||
        CompareDates(_moCal.selectedDate, [self todayDate]) != 0 ||
        ![defaults boolForKey:kShowOverdueReminders]) {
        return @[];
    }
    NSArray *overdue = [_ec remindersDueBeforeDate:[_nsCal startOfDayForDate:[NSDate new]]];
    if (overdue.count == 0) return @[];
    AgendaOverdueHeading *heading = [AgendaOverdueHeading new];
    heading.count = overdue.count;
    heading.expanded = [defaults boolForKey:kOverdueSectionExpanded];
    return heading.expanded ? [@[heading] arrayByAddingObjectsFromArray:overdue] : @[heading];
}

- (void)agendaWantsToToggleOverdueSection
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:![defaults boolForKey:kOverdueSectionExpanded] forKey:kOverdueSectionExpanded];
    [self updateAgenda];
}

#pragma mark -
#pragma mark Time

- (MoDate)todayDate
{
    return [DualTZBridge beijingTodayMoDate];
}

- (void)resetCalendarToToday
{
    _lastBeijingToday = [DualTZBridge beijingTodayMoDate];
    _moCal.beijingTodayDate = _lastBeijingToday;
    _moCal.todayDate = MakeDateWithNSDate([NSDate new], [NSCalendar autoupdatingCurrentCalendar]);
    _moCal.selectedDate = _lastBeijingToday;
    _moCal.showDualToday = [[NSUserDefaults standardUserDefaults] boolForKey:kDualTZShowDualToday];
}

- (NSInteger)minutesUntilNextJoinableMeeting
{
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kDualTZShowUpcomingCountdown]) return 0;
    NSDate *now = NSDate.date;
    MoDate bjToday = [self todayDate];
    NSArray *candidates = [([self eventsForDate:bjToday] ?: @[]) arrayByAddingObjectsFromArray:([self eventsForDate:AddDaysToDate(1, bjToday)] ?: @[])];
    NSTimeInterval minSeconds = MAXFLOAT;
    for (EventInfo *info in candidates) {
        if (!info.event || info.event.isAllDay || !info.meetingURL) continue;
        NSTimeInterval diff = [info.event.startDate timeIntervalSinceDate:now];
        if (diff > 0 && diff <= 15 * 60 && diff < minSeconds) {
            minSeconds = diff;
        }
    }
    return minSeconds < MAXFLOAT ? MAX(1, (NSInteger)ceil(minSeconds / 60.0)) : 0;
}

- (NSString *)upcomingMeetingCountdownSuffix
{
    if (_upcomingCountdownMinutes <= 0) return @"";
    if ([DualTZBridge isChineseLanguage]) {
        return [NSString stringWithFormat:@" · %zdm后开会", _upcomingCountdownMinutes];
    }
    return [NSString stringWithFormat:@" · in %zdm", _upcomingCountdownMinutes];
}

- (void)showMeetingIndicatorIfNecessary
{
    BOOL show = NO;
    MoDate bjToday = [self todayDate];
    NSArray *todayEvents = [([self eventsForDate:bjToday] ?: @[]) arrayByAddingObjectsFromArray:([self eventsForDate:AddDaysToDate(1, bjToday)] ?: @[])];
    for (EventInfo *info in todayEvents) {
        if (info.event == nil) continue;
        NSDate *fifteenMinutesPrior = MeetingJoinableThreshold(info.event, _nsCal);
        if (info.meetingURL && !info.event.isAllDay
            && [fifteenMinutesPrior compare:NSDate.date] == NSOrderedAscending
            && [NSDate.date compare:info.event.endDate] == NSOrderedAscending) {
            show = YES;
            break;
        }
    }
    NSInteger nextMins = [self minutesUntilNextJoinableMeeting];
    if (_shouldShowMeetingIndicator != show || _upcomingCountdownMinutes != nextMins) {
        _shouldShowMeetingIndicator = show;
        _upcomingCountdownMinutes = nextMins;
        [self updateMenubarIcon];
    }
}

- (float)volumeRelativeToSystemVolumeWithCap:(float)cap
{
    // https://stackoverflow.com/a/8953438/111418
    AudioDeviceID deviceID;
    UInt32 dataSize = sizeof(deviceID);
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    propertyAddress.mScope    = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement  = kAudioObjectPropertyElementMain;

    OSStatus result = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize, &deviceID);

    if (kAudioHardwareNoError != result) return cap;
    
    propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
    propertyAddress.mScope    = kAudioDevicePropertyScopeOutput;
    propertyAddress.mElement  = 1; // Channel 0  is main, if available

    if (!AudioObjectHasProperty(deviceID, &propertyAddress)) return cap;

    Float32 volume;
    dataSize = sizeof(volume);

    result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, NULL, &dataSize, &volume);

    if (kAudioHardwareNoError != result) return cap;
    
    return (volume >= cap) ? cap / volume : 1;
}

- (void)updateTimer
{
    NSDate *now = [NSDate date];
    NSDateComponents *components = [_nsCal components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:now];

    // Should we beep-beep on the hour? If so, cap the volume relative to the
    // system volume so it's not too loud.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kBeepBeepOnTheHour]
        && components.minute == 0
        && components.second == 0) {
        NSSound *beepbeep = [NSSound soundNamed:@"beep"];
        // See if the user has put their own beep.mp3 in our Application
        // Support folder. The user-supplied sound is in a folder named for
        // our bundle identifier.
        NSURL *beepURL = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        if (beepURL) {
            NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
            beepURL = [beepURL URLByAppendingPathComponent:bundleID isDirectory:YES];
            beepURL = [beepURL URLByAppendingPathComponent:@"beep.mp3" isDirectory:NO];
            if ([NSFileManager.defaultManager fileExistsAtPath:beepURL.path isDirectory:NULL]) {
                beepbeep = [[NSSound alloc] initWithContentsOfURL:beepURL byReference:NO];
            }
        }
        [beepbeep setVolume:[self volumeRelativeToSystemVolumeWithCap:0.12]];
        [beepbeep play];
    }

    // Set up _timer to fire on next minute or second.
    NSDate *fireDate;
    if (_clockUsesSeconds) {
        NSTimeInterval nowSeconds = [now timeIntervalSinceReferenceDate];
        NSTimeInterval nextSecond = floor(nowSeconds) + 1.0;
        fireDate = [NSDate dateWithTimeIntervalSinceReferenceDate:nextSecond];
    }
    else {
        NSDateComponents *comp = [NSDateComponents new];
        comp.second = 0;
        fireDate = [_nsCal nextDateAfterDate:now matchingComponents:comp options:NSCalendarMatchNextTime];
    }
    [_timer invalidate];
    _timer = [[NSTimer alloc] initWithFireDate:fireDate interval:0 target:self selector:@selector(updateTimer) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    
    // Check if past events should be dimmed each minute.
    // Also check if we should show the meeting indicator.
    static NSTimeInterval dimEventsTime = 0;
    NSTimeInterval currentTime = MonotonicClockTime();
    NSTimeInterval elapsedTime = currentTime - dimEventsTime;
    if (elapsedTime > 60 || fabs(elapsedTime - 60) < 0.5) {
        [_agendaVC dimEventsIfNecessary];
        dimEventsTime = currentTime;
        [self showMeetingIndicatorIfNecessary];
    }
    // Reset calendar to today after 10 minutes of inactivity.
    elapsedTime = currentTime - _inactiveTime;
    if (_inactiveTime && (elapsedTime > 600 || fabs(elapsedTime - 600) < 0.5)) {
        [self resetCalendarToToday];
        _inactiveTime = 0;
    }
    // 检查北京是否跨过午夜 00:00 进入次日，确保即使系统未换日也能同步刷新双今标、选中锚点与图标
    MoDate currentBJToday = [DualTZBridge beijingTodayMoDate];
    BOOL bjDayChanged = CompareDates(currentBJToday, _lastBeijingToday) != 0;
    if (bjDayChanged) {
        MoDate prevBJ = _lastBeijingToday;
        _lastBeijingToday = currentBJToday;
        _moCal.beijingTodayDate = currentBJToday;
        _moCal.todayDate = MakeDateWithNSDate([NSDate new], [NSCalendar autoupdatingCurrentCalendar]);
        if (CompareDates(_moCal.selectedDate, prevBJ) == 0) {
            _moCal.selectedDate = currentBJToday;
        }
        [self updateAgenda];
        [self updateMenubarIcon];
    }
    if (self.itsycalWindow.isVisible) {
        [_heroHeaderView refresh];
        BOOL prevDSTVisible = !_dstBannerView.isHidden;
        [_dstBannerView refresh];
        if (prevDSTVisible != _dstBannerView.shouldShow) {
            [self updateTopStackLayout];
        }
    }
    // Update clock if necessary.
    if (_clockUsesTime && !bjDayChanged) [self updateMenubarIcon];
}

#pragma mark -
#pragma mark Custom clock format

- (NSString *)effectiveClockFormat
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kDualTZMenuBarEnabled]) {
        return [defaults stringForKey:kDualTZMenuBarFormat];
    }
    return [defaults stringForKey:kClockFormat];
}

- (void)clockFormatDidChange
{
    NSString *format = [self effectiveClockFormat];
    BOOL dualEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kDualTZMenuBarEnabled];

    // Did the user set a custom clock format string?
    if (format != nil && ![format isEqualToString:@""]) {
        if (dualEnabled) {
            _clockUsesTime = [DualTZBridge templateUsesTime:format];
            _clockUsesSeconds = [DualTZBridge templateUsesSeconds:format];
        } else {
            [self processFormatForTimeAndSecondsSpecifiers:format];
        }
        _clockFormat = format;
    }
    else {
        _clockUsesTime = NO;
        _clockUsesSeconds = NO;
        _clockFormat = nil;
        _statusItem.button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
        _statusItem.button.title = @"";
    }
    [self updateStatusItemFont];
    [self updateMenubarIcon];
    [self updateTimer];
}

- (void)processFormatForTimeAndSecondsSpecifiers:(NSString *)format
{
    // A time specifier is one of the following: a, H, h, K, k, j, m, s.
    // The seconds specifier is an s-character. Does format contain
    // a time specifier or s that isn't inside a quoted string? a quoted
    // string is delimited by single-quote chars.

    NSString *timeSpecifiers = @"aHhKkjms";
    
    __block BOOL timeSpecifierFound = NO;
    __block BOOL secondsSpecifierFound = NO;
    __block BOOL insideQuotedString = NO;

    // First, remove adjacent pairs of single-quotes. They
    // represent single-quote literals. Removing them makes
    // parsing for quoted strings much easier.
    NSString *fmt = [format stringByReplacingOccurrencesOfString:@"''" withString:@""];

    // Iterate through fmt looking for an s that isn't in a quoted string.
    [fmt enumerateSubstringsInRange: NSMakeRange(0, [fmt length]) options: NSStringEnumerationByComposedCharacterSequences usingBlock: ^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {

        // Did we find an s that isn't inside a quoted string?
        if (insideQuotedString == NO && [substring isEqualToString:@"s"]) {
            secondsSpecifierFound = YES;
            timeSpecifierFound = YES;
            *stop = YES;
        }
        // Did we find a time specifier that isn't inside a quoted string?
        else if (insideQuotedString == NO && [timeSpecifiers containsString:substring]) {
            timeSpecifierFound = YES;
        }
        // Are we inside a quoted string? They are delimited with single-quotes.
        else if ([substring isEqualToString:@"'"]) {
            insideQuotedString = !insideQuotedString;
        }
    }];
    _clockUsesTime = timeSpecifierFound;
    _clockUsesSeconds = secondsSpecifierFound;
}

#pragma mark -
#pragma mark Notifications

- (void)fileNotifications
{
    __weak typeof(self) weakSelf = self;
    id token;

    // Day changed notification
    token = [[NSNotificationCenter defaultCenter] addObserverForName:NSCalendarDayChangedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        MoDate selectedDate = strongSelf->_moCal.selectedDate;
        [strongSelf resetCalendarToToday];
        [strongSelf updateMenubarIcon];
        [strongSelf updateTimer];
        // Reminders due yesterday are now overdue. Changing the selected
        // date rebuilds the agenda; if it didn't change, rebuild it here.
        if (CompareDates(selectedDate, strongSelf->_moCal.selectedDate) == 0) {
            [strongSelf updateAgenda];
        }
    }];
    [_notificationTokens addObject:token];

    // Timezone changed notification
    token = [[NSNotificationCenter defaultCenter] addObserverForName:NSSystemTimeZoneDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateMenubarIcon];
        [strongSelf updateTimer];
        [strongSelf->_ec refetchAll];
    }];
    [_notificationTokens addObject:token];

    // Locale notifications
    token = [[NSNotificationCenter defaultCenter] addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateMenubarIcon];
        [strongSelf updateTimer];
        [strongSelf updateAgenda]; // 12/24 hr time change in sys prefs
    }];
    [_notificationTokens addObject:token];

    // System clock notification
    token = [[NSNotificationCenter defaultCenter] addObserverForName:NSSystemClockDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateMenubarIcon];
        [strongSelf updateTimer];
        [strongSelf->_ec refetchAll];
    }];
    [_notificationTokens addObject:token];

    // Wake from sleep notification
    token = [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateMenubarIcon];
        [strongSelf updateTimer];
    }];
    [_notificationTokens addObject:token];

    // 监听中国节假日调休 JSON 更新通知，实时重绘月历休/班标记
    token = [[NSNotificationCenter defaultCenter] addObserverForName:[DualTZBridge holidaysDidChangeNotificationName] object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf->_moCal updateCalendar];
        [strongSelf updateAgenda];
    }];
    [_notificationTokens addObject:token];

    // Observe NSUserDefaults for preference changes
    for (NSString *keyPath in ObservedDefaultsKeys()) {
        [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:NULL];
    }
}

#pragma mark -
#pragma mark NSUserDefaults observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:kShowEventDays]) {
        // More agenda days can extend the fetch range (see -fetchEndDate).
        // Fetching does nothing if those days are already cached.
        [self updateAgenda];
        [_ec fetchEvents];
    }
    else if ([keyPath isEqualToString:kShowDaysWithNoEventsInAgenda] ||
        [keyPath isEqualToString:kShowOverdueReminders]) {
        [self updateAgenda];
    }
    else if ([keyPath isEqualToString:kMenuBarIconType] ||
             [keyPath isEqualToString:kShowMonthInIcon] ||
             [keyPath isEqualToString:kShowDayOfWeekInIcon] ||
             [keyPath isEqualToString:kShowMeetingIndicator] ||
             [keyPath isEqualToString:kHideIcon] ||
             [keyPath isEqualToString:kBaselineOffset] ||
             [keyPath isEqualToString:kDualTZIconFollowsBeijing] ||
             [keyPath isEqualToString:kDualTZShowUpcomingCountdown]) {
        [self showMeetingIndicatorIfNecessary];
        [self updateMenubarIcon];
    }
    else if ([keyPath isEqualToString:kDualTZAppLanguage]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:[DualTZBridge languageDidChangeNotificationName] object:nil];
        [DualTZBridge syncMenuTemplateFromTokens];
        [self updateTopStackLayout];
        [_heroHeaderView refresh];
        [_scrubberView refreshAppearanceAndRef];
        [self clockFormatDidChange];
        [self updateAgenda];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self rebuildPrefsWindowForLanguageChange];
        });
    }
    else if ([keyPath isEqualToString:kClockFormat] ||
             [keyPath isEqualToString:kDualTZMenuBarEnabled] ||
             [keyPath isEqualToString:kDualTZMenuBarFormat] ||
             [keyPath isEqualToString:kDualTZMenuUseAdvanced] ||
             [keyPath isEqualToString:kDualTZMenuTokensJSON]) {
        [self clockFormatDidChange];
    }
    else if ([keyPath isEqualToString:kDualTZWindowGlassStyle]) {
        ItsycalGlassStyle style = (ItsycalGlassStyle)[[NSUserDefaults standardUserDefaults] integerForKey:kDualTZWindowGlassStyle];
        [self.itsycalWindow applyGlassStyle:style];
        [_moCal setNeedsDisplay:YES];
        [self updateAgenda];
    }
    else if ([keyPath isEqualToString:kDualTZPrimaryTimeZoneID] ||
             [keyPath isEqualToString:kDualTZPrimaryCityAlias] ||
             [keyPath isEqualToString:kDualTZSecondaryCitiesJSON] ||
             [keyPath isEqualToString:kDualTZWorldClockOffsetRef] ||
             [keyPath isEqualToString:kDualTZWorldClockCollapsed]) {
        _lastBeijingToday = [DualTZBridge beijingTodayMoDate];
        _moCal.beijingTodayDate = _lastBeijingToday;
        [self updateTopStackLayout];
        [_heroHeaderView refresh];
        [_moCal updateCalendar];
        [self updateMenubarIcon];
        [self updateAgenda];
    }
    else if ([keyPath isEqualToString:kDualTZShowHeroHeader] ||
             [keyPath isEqualToString:kDualTZShowDSTWarning] ||
             [keyPath isEqualToString:kDualTZDismissedDSTDate]) {
        [self updateTopStackLayout];
        [_heroHeaderView refresh];
    }
    else if ([keyPath isEqualToString:kDualTZShowLunarSolarTerms] ||
             [keyPath isEqualToString:kDualTZShowChinaHolidays] ||
             [keyPath isEqualToString:kDualTZShowUSHolidays] ||
             [keyPath isEqualToString:kDualTZShowMarketingNodes]) {
        [_heroHeaderView refresh];
        [SizePref notifySizeChanged];
        [_moCal updateCalendar];
        [self updateAgenda];
    }
    else if ([keyPath isEqualToString:kDualTZShowAgendaHolidays] ||
             [keyPath isEqualToString:kDualTZShowAgendaDualTZ]) {
        [self updateAgenda];
    }
    else if ([keyPath isEqualToString:kDualTZShowThirdRefTZ]) {
        [_heroHeaderView refresh];
        [_scrubberView refreshAppearanceAndRef];
    }
    else if ([keyPath isEqualToString:kDualTZEnableTimeScrubber] ||
             [keyPath isEqualToString:kDualTZTimeScrubberExpanded]) {
        [self updateScrubberState];
    }
    else if ([keyPath isEqualToString:kDualTZShowDualToday]) {
        _moCal.showDualToday = [[NSUserDefaults standardUserDefaults] boolForKey:kDualTZShowDualToday];
    }
    else if ([keyPath isEqualToString:kShowCompletedReminders]) {
        // Completed reminders are only fetched when shown.
        [_ec refetchAll];
    }
    else if ([keyPath isEqualToString:kWindowPosition]) {
        // Move Itsycal now if it is showing (e.g., when pinned).
        if (self.itsycalWindow.isVisible) {
            [self positionItsycalWindowForInitialPresentation:YES];
        }
    }
}

@end

