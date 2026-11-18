//
//  Created by Sanjay Madan on 1/11/17.
//  Copyright © 2017 mowglii.com. All rights reserved.
//

#import "PrefsGeneralVC.h"
#import "Itsycal.h"
#import "MoLoginItem.h"
#import "MoVFLHelper.h"
#import "MASShortcut/Shortcut.h"

@implementation PrefsGeneralVC
{
    NSButton *_login;
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

    // 应用内中英文即时切换下拉框
    NSTextField *langLabel = label(DualTZLoc(@"dualtz.lang.label"));
    NSPopUpButton *langPopup = [NSPopUpButton new];
    [langPopup addItemsWithTitles:@[DualTZLoc(@"dualtz.lang.zh"),
                                    DualTZLoc(@"dualtz.lang.en"),
                                    DualTZLoc(@"dualtz.lang.system")]];
    [langPopup itemAtIndex:0].tag = 0;
    [langPopup itemAtIndex:1].tag = 1;
    [langPopup itemAtIndex:2].tag = 2;
    [langPopup.cell setAccessibilityTitleUIElement:langLabel.cell];
    [v addSubview:langPopup];

    // Checkboxes
    _login = chkbx(DualTZLoc(@"Launch at login"));
    _login.action = @selector(launchAtLogin:);
    NSButton *beepBeep = chkbx(DualTZLoc(@"Beep beep on the hour"));

    // Shortcut label
    NSTextField *shortcutLabel = label(DualTZLoc(@"Keyboard shortcut"));

    // Shortcut view
    MASShortcutView *shortcutView = [MASShortcutView new];
    [shortcutView setAssociatedUserDefaultsKey:kKeyboardShortcut withTransformerName:MASDictionaryTransformerName];
    [v addSubview:shortcutView];

    // Window position label
    NSTextField *positionLabel = label(DualTZLoc(@"Window position:"));

    // Window position popup
    NSPopUpButton *positionPopup = [NSPopUpButton new];
    [positionPopup addItemsWithTitles:@[DualTZLoc(@"Below menu bar icon"),
                                        DualTZLoc(@"Top right of screen")]];
    [positionPopup itemAtIndex:0].tag = WindowPositionBelowMenuBarIcon;
    [positionPopup itemAtIndex:1].tag = WindowPositionTopRightOfScreen;
    [positionPopup.cell setAccessibilityTitleUIElement:positionLabel.cell];
    [v addSubview:positionPopup];

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @20} views:NSDictionaryOfVariableBindings(langLabel, langPopup, _login, beepBeep, shortcutLabel, shortcutView, positionLabel, positionPopup)];
    [vfl :@"V:|-m-[langPopup]-m-[_login]-[beepBeep]-m-[shortcutLabel]-3-[shortcutView(25)]-30-[positionPopup]-m-|"];
    [vfl :@"H:|-m-[langLabel]-[langPopup]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[_login]-(>=m)-|"];
    [vfl :@"H:|-m-[beepBeep]-(>=m)-|"];
    [vfl :@"H:|-(>=m)-[shortcutLabel]-(>=m)-|"];
    [vfl :@"H:|-m-[shortcutView(>=220)]-m-|"];
    [vfl :@"H:|-m-[positionLabel]-[positionPopup]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];

    // Center shortcutLabel
    [v addConstraint:[NSLayoutConstraint constraintWithItem:shortcutLabel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:v attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];

    // 绑定语言偏好
    [langPopup bind:@"selectedTag" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kDualTZAppLanguage] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Binding for hourly beep
    [beepBeep bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kBeepBeepOnTheHour] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for window position
    [positionPopup bind:@"selectedTag" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kWindowPosition] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    self.view = v;
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    // The API used to check the login item's state (LSSharedFileList) causes
    // errors for users who have network drives but are not connected to their
    // network (github.com/sfsam/Itsycal/issues/15). Give them an option to
    // disable this check.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDoNotCheckLoginItemStatus] == NO) {
        _login.hidden = NO;
        _login.state = MOIsLoginItemEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    }
    else {
        _login.hidden = YES;
    }
}

#pragma mark -
#pragma mark Login item

- (void)launchAtLogin:(NSButton *)login
{
    MOEnableLoginItem(login.state == NSControlStateValueOn);
}

@end
