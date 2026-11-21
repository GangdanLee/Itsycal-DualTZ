//
//  Itsycal.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/3/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "Itsycal.h"
#import "Itsycal-Swift.h"

// NSUserDefaults keys
NSString * const kPinItsycal = @"PinItsycal";
NSString * const kShowEventDays = @"ShowEventDays";
NSString * const kShowWeeks = @"ShowWeeks";
NSString * const kWeekStartDOW = @"WeekStartDOW";
NSString * const kHighlightedDOWs = @"HighlightedDOWs";
NSString * const kKeyboardShortcut = @"GlobalShortcut";
NSString * const kMenuBarIconType = @"MenuBarIconType";
NSString * const kShowMonthInIcon = @"ShowMonthInIcon";
NSString * const kShowDayOfWeekInIcon = @"ShowDayOfWeekInIcon";
NSString * const kShowMeetingIndicator = @"ShowMeetingIndicator";
NSString * const kAllowOutsideApplicationsFolder = @"AllowOutsideApplicationsFolder";
NSString * const kClockFormat = @"ClockFormat";
NSString * const kHideIcon = @"HideIcon";
NSString * const kShowLocation = @"ShowLocation";
NSString * const kShowEventDots = @"kShowEventDots";
NSString * const kUseColoredDots = @"UseColoredDots";
NSString * const kBeepBeepOnTheHour = @"BeepBeepOnTheHour";
NSString * const kBaselineOffset = @"BaselineOffset";
NSString * const kEnableMeetingButtonIndefinitely = @"EnableMeetingButtonIndefinitely";
NSString * const kDoNotDrawOutlineAroundCurrentMonth = @"DoNotDrawOutlineAroundCurrentMonth";
NSString * const kShowDaysWithNoEventsInAgenda = @"ShowDaysWithNoEventsInAgenda";
NSString * const kShowCompletedReminders = @"ShowCompletedReminders";
NSString * const kShowOverdueReminders = @"ShowOverdueReminders";
NSString * const kOverdueSectionExpanded = @"OverdueSectionExpanded";
NSString * const kShowEventPopoverOnHover = @"ShowEventPopoverOnHover";
NSString * const kDoNotCheckLoginItemStatus = @"DoNotCheckLoginItemStatus";
NSString * const kWindowPosition = @"WindowPosition";
NSString * const kTimerEndDate = @"TimerEndDate";
NSString * const kTimerRecentMinutes = @"TimerRecentMinutes";

// DualTZ 扩展配置键
NSString * const kDualTZMenuBarEnabled = @"DualTZMenuBarEnabled";
NSString * const kDualTZMenuBarFormat = @"DualTZMenuBarFormat";
NSString * const kDualTZIconFollowsBeijing = @"DualTZIconFollowsBeijing";
NSString * const kDualTZShowHeroHeader = @"DualTZShowHeroHeader";
NSString * const kDualTZShowDualToday = @"DualTZShowDualToday";
NSString * const kDualTZShowLunarSolarTerms = @"DualTZShowLunarSolarTerms";
NSString * const kDualTZShowChinaHolidays = @"DualTZShowChinaHolidays";
NSString * const kDualTZShowUSHolidays = @"DualTZShowUSHolidays";
NSString * const kDualTZShowAgendaDualTZ = @"DualTZShowAgendaDualTZ";
NSString * const kDualTZAllowBJEventCreate = @"DualTZAllowBJEventCreate";
NSString * const kDualTZEnableTimeScrubber = @"DualTZEnableTimeScrubber";
NSString * const kDualTZTimeScrubberExpanded = @"DualTZTimeScrubberExpanded";
NSString * const kDualTZShowThirdRefTZ = @"DualTZShowThirdRefTZ";
NSString * const kDualTZShowDSTWarning = @"DualTZShowDSTWarning";
NSString * const kDualTZDismissedDSTDate = @"DualTZDismissedDSTDate";
NSString * const kDualTZHasImportedUpstreamPrefs = @"DualTZHasImportedUpstreamPrefs";
NSString * const kDualTZShowAgendaHolidays = @"DualTZShowAgendaHolidays";
NSString * const kDualTZHasMigratedAgendaPreview = @"DualTZHasMigratedAgendaPreview";
NSString * const kDualTZAppLanguage = @"DualTZAppLanguage";
NSString * const kDualTZShowMarketingNodes = @"DualTZShowMarketingNodes";
NSString * const kDualTZShowUpcomingCountdown = @"DualTZShowUpcomingCountdown";
NSString * const kDualTZWindowGlassStyle = @"DualTZWindowGlassStyle";
NSString * const kDualTZPrimaryTimeZoneID = @"DualTZPrimaryTimeZoneID";
NSString * const kDualTZPrimaryCityAlias = @"DualTZPrimaryCityAlias";
NSString * const kDualTZSecondaryCitiesJSON = @"DualTZSecondaryCitiesJSON";
NSString * const kDualTZWorldClockOffsetRef = @"DualTZWorldClockOffsetRef";
NSString * const kDualTZWorldClockCollapsed = @"DualTZWorldClockCollapsed";
NSString * const kDualTZWarnLateNight = @"DualTZWarnLateNight";
NSString * const kDualTZMenuUseAdvanced = @"DualTZMenuUseAdvanced";
NSString * const kDualTZMenuTokensJSON = @"DualTZMenuTokensJSON";
NSString * const kDualTZSubscriptionsJSON = @"DualTZSubscriptionsJSON";
NSString * const kDualTZShowSubscriptionBar = @"DualTZShowSubscriptionBar";
NSString * const kDualTZSubscriptionBarExpanded = @"DualTZSubscriptionBarExpanded";

NSString *DualTZLocalizedString(NSString *key, NSString *defaultValue)
{
    return [DualTZBridge localizedStringForKey:(key ?: @"") defaultValue:defaultValue];
}

@implementation NSDate (HasNoEvents)

- (BOOL)hasNoEvents
{
    NSNumber *num = objc_getAssociatedObject(self, @selector(hasNoEvents));
    return [num boolValue];
}

- (void)setHasNoEvents:(BOOL)hasNoEvents
{
    objc_setAssociatedObject(self, @selector(hasNoEvents), @(hasNoEvents), OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)isSelectedAnchorDate
{
    NSNumber *num = objc_getAssociatedObject(self, @selector(isSelectedAnchorDate));
    return [num boolValue];
}

- (void)setIsSelectedAnchorDate:(BOOL)isSelectedAnchorDate
{
    objc_setAssociatedObject(self, @selector(isSelectedAnchorDate), @(isSelectedAnchorDate), OBJC_ASSOCIATION_RETAIN);
}

@end
