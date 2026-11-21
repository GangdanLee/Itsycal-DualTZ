//
//  Itsycal.h
//  Itsycal
//
//  Created by Sanjay Madan on 2/3/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>
#import "MoDate.h"

// NSUserDefaults keys
extern NSString * const kPinItsycal;
extern NSString * const kShowEventDays;
extern NSString * const kShowWeeks;
extern NSString * const kWeekStartDOW;
extern NSString * const kHighlightedDOWs;
extern NSString * const kKeyboardShortcut;
extern NSString * const kMenuBarIconType; // 0 = solid round rect (default), 1 = outlined round rect,
                                          // 2 = generic calendar icon, 3 = Itsycal icon
extern NSString * const kShowMonthInIcon;
extern NSString * const kShowDayOfWeekInIcon;
extern NSString * const kShowMeetingIndicator;
extern NSString * const kAllowOutsideApplicationsFolder;
extern NSString * const kClockFormat;
extern NSString * const kHideIcon;
extern NSString * const kShowLocation;
extern NSString * const kShowEventDots;
extern NSString * const kUseColoredDots;
extern NSString * const kBeepBeepOnTheHour;
extern NSString * const kBaselineOffset;
extern NSString * const kEnableMeetingButtonIndefinitely;
extern NSString * const kDoNotDrawOutlineAroundCurrentMonth;
extern NSString * const kShowDaysWithNoEventsInAgenda;
extern NSString * const kShowCompletedReminders;
extern NSString * const kShowOverdueReminders;
extern NSString * const kOverdueSectionExpanded;
extern NSString * const kShowEventPopoverOnHover;
extern NSString * const kDoNotCheckLoginItemStatus;
extern NSString * const kWindowPosition;
extern NSString * const kTimerEndDate;
extern NSString * const kTimerRecentMinutes;

// DualTZ 扩展配置键
extern NSString * const kDualTZMenuBarEnabled;
extern NSString * const kDualTZMenuBarFormat;
extern NSString * const kDualTZIconFollowsBeijing;
extern NSString * const kDualTZShowHeroHeader;
extern NSString * const kDualTZShowDualToday;
extern NSString * const kDualTZShowLunarSolarTerms;
extern NSString * const kDualTZShowChinaHolidays;
extern NSString * const kDualTZShowUSHolidays;
extern NSString * const kDualTZShowAgendaDualTZ;
extern NSString * const kDualTZAllowBJEventCreate;
extern NSString * const kDualTZEnableTimeScrubber;
extern NSString * const kDualTZTimeScrubberExpanded;
extern NSString * const kDualTZShowThirdRefTZ;
extern NSString * const kDualTZShowDSTWarning;
extern NSString * const kDualTZDismissedDSTDate;
extern NSString * const kDualTZHasImportedUpstreamPrefs;
extern NSString * const kDualTZShowAgendaHolidays;
extern NSString * const kDualTZHasMigratedAgendaPreview;
extern NSString * const kDualTZAppLanguage;
extern NSString * const kDualTZShowMarketingNodes;
extern NSString * const kDualTZShowUpcomingCountdown;
extern NSString * const kDualTZWindowGlassStyle;
extern NSString * const kDualTZPrimaryTimeZoneID;
extern NSString * const kDualTZPrimaryCityAlias;
extern NSString * const kDualTZSecondaryCitiesJSON;
extern NSString * const kDualTZWorldClockOffsetRef;
extern NSString * const kDualTZWorldClockCollapsed;
extern NSString * const kDualTZWarnLateNight;
extern NSString * const kDualTZMenuUseAdvanced;
extern NSString * const kDualTZMenuTokensJSON;
extern NSString * const kDualTZSubscriptionsJSON;
extern NSString * const kDualTZShowSubscriptionBar;
extern NSString * const kDualTZSubscriptionBarExpanded;
extern NSString * const kDualTZAIQuotaAccountsJSON;
extern NSString * const kDualTZAIQuotaSnapshotsJSON;
extern NSString * const kDualTZShowAIQuotaPool;

// 应用内中英文即时切换本地化入口（0=简体中文, 1=English, 2=跟随系统）
NSString *DualTZLocalizedString(NSString *key, NSString *defaultValue);
#define DualTZLoc(key) DualTZLocalizedString((key), nil)

typedef NS_ENUM(NSInteger, WindowPosition) {
    WindowPositionBelowMenuBarIcon = 0,
    WindowPositionTopRightOfScreen = 1
};

// Set an associated object on NSDate to indicate
// whether of not this date has events.
// https://stackoverflow.com/a/16708352
@interface NSDate (HasNoEvents)
@property (nonatomic) BOOL hasNoEvents;
@property (nonatomic) BOOL isSelectedAnchorDate;
@end
