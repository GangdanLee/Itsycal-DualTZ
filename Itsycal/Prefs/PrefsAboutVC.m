//
//  Created by Sanjay Madan on 1/11/17.
//  Copyright © 2017 mowglii.com. All rights reserved.
//

#import "PrefsAboutVC.h"
#import "Itsycal.h"
#import "MoTextField.h"
#import "MoVFLHelper.h"

@implementation PrefsAboutVC

#pragma mark -
#pragma mark View lifecycle

- (MoTextField *)labelInView:(NSView *)box text:(NSString *)text url:(NSString *)urlString
{
    MoTextField *txt = [MoTextField labelWithString:text];
    txt.translatesAutoresizingMaskIntoConstraints = NO;
    if (urlString != nil) {
        txt.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        txt.linkEnabled = YES;
        txt.urlString = urlString;
    }
    [box addSubview:txt];
    return txt;
}

- (NSView *)addHeaderInBox:(NSView *)box
{
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSTextField *appName = [self labelInView:box text:@"Itsycal DualTZ" url:nil];
    appName.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];

    NSString *verText = [NSString stringWithFormat:@"%@ (%@)", infoDict[@"CFBundleShortVersionString"] ?: @"1.0.0", infoDict[@"CFBundleVersion"] ?: @"1000"];
    NSTextField *version = [self labelInView:box text:verText url:nil];
    version.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    version.textColor = [NSColor secondaryLabelColor];

    NSTextField *tagline = [self labelInView:box text:DualTZLoc(@"dualtz.about.tagline") url:nil];
    tagline.font = [NSFont systemFontOfSize:11.5];
    tagline.textColor = [NSColor secondaryLabelColor];

    [NSLayoutConstraint activateConstraints:@[
        [appName.topAnchor constraintEqualToAnchor:box.topAnchor],
        [appName.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [version.leadingAnchor constraintEqualToAnchor:appName.trailingAnchor constant:6],
        [version.firstBaselineAnchor constraintEqualToAnchor:appName.firstBaselineAnchor],
        [version.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor],
        [tagline.topAnchor constraintEqualToAnchor:appName.bottomAnchor constant:4],
        [tagline.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [tagline.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor],
    ]];
    return tagline;
}

- (NSView *)addLinksInBox:(NSView *)box belowView:(NSView *)prev
{
    NSArray<NSArray<NSString *> *> *links = @[
        @[@"⭐", DualTZLoc(@"dualtz.about.github"), @"https://github.com/GangdanLee/Itsycal-DualTZ"],
        @[@"📦", DualTZLoc(@"dualtz.about.releases"), @"https://github.com/GangdanLee/Itsycal-DualTZ/releases"],
        @[@"💬", DualTZLoc(@"dualtz.about.issues"), @"https://github.com/GangdanLee/Itsycal-DualTZ/issues"],
        @[@"🙏", DualTZLoc(@"dualtz.about.upstream"), @"https://github.com/sfsam/Itsycal"],
    ];
    for (NSUInteger i = 0; i < links.count; i++) {
        NSTextField *emoji = [self labelInView:box text:links[i][0] url:nil];
        [emoji.cell setAccessibilityElement:NO];
        MoTextField *link = [self labelInView:box text:links[i][1] url:links[i][2]];
        CGFloat gap = (i == 0) ? 18.0 : 10.0;
        [NSLayoutConstraint activateConstraints:@[
            [link.topAnchor constraintEqualToAnchor:prev.bottomAnchor constant:gap],
            [emoji.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
            [link.leadingAnchor constraintEqualToAnchor:emoji.trailingAnchor constant:6],
            [link.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor],
            [emoji.firstBaselineAnchor constraintEqualToAnchor:link.firstBaselineAnchor],
        ]];
        prev = link;
    }
    return prev;
}

- (void)addFooterInBox:(NSView *)box belowView:(NSView *)prev
{
    NSTextField *copyYear = [self labelInView:box text:@"© 2026" url:nil];
    copyYear.font = [NSFont systemFontOfSize:11.5];
    MoTextField *copyAuthor = [self labelInView:box text:@"Morgan Lee · MIT License" url:@"https://github.com/GangdanLee/Itsycal-DualTZ"];
    copyAuthor.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    NSTextField *upstreamCopy = [self labelInView:box text:DualTZLoc(@"dualtz.about.upstream_copy") url:nil];
    upstreamCopy.font = [NSFont systemFontOfSize:10.5];
    upstreamCopy.textColor = [NSColor tertiaryLabelColor];

    [NSLayoutConstraint activateConstraints:@[
        [copyYear.topAnchor constraintEqualToAnchor:prev.bottomAnchor constant:20],
        [copyYear.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [copyAuthor.leadingAnchor constraintEqualToAnchor:copyYear.trailingAnchor constant:4],
        [copyAuthor.firstBaselineAnchor constraintEqualToAnchor:copyYear.firstBaselineAnchor],
        [copyAuthor.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor],
        [upstreamCopy.topAnchor constraintEqualToAnchor:copyYear.bottomAnchor constant:4],
        [upstreamCopy.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [upstreamCopy.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor],
        [upstreamCopy.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
    ]];
}

- (void)loadView
{
    NSView *v = [NSView new];
    NSView *box = [NSView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:box];

    NSView *tagline = [self addHeaderInBox:box];
    NSView *lastLink = [self addLinksInBox:box belowView:tagline];
    [self addFooterInBox:box belowView:lastLink];

    MoVFLHelper *outer = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @25} views:NSDictionaryOfVariableBindings(box)];
    [outer :@"V:|-m-[box]-m-|"];
    [outer :@"H:|-(>=m)-[box]-(>=m)-|"];
    [box.centerXAnchor constraintEqualToAnchor:v.centerXAnchor].active = YES;

    NSLayoutConstraint *hug = [box.widthAnchor constraintEqualToConstant:0];
    hug.priority = 1;
    hug.active = YES;

    self.view = v;
}

@end
