// The Animated lock screen rows, put on the Lock screen widget page by Shared/Player/PlayerSettings.m, and
// the Sources row for an order of these sources (the redesigned player keeps one of its own).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGOrderPage.h"
#import "Settings/SGPageStyle.h"
#import "LockScreenArtwork.h"

static void sayWhatIsMissing(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"动态锁屏封面"
        message:[NSString stringWithFormat:@"动态封面属于锁屏功能，iOS 26 起才支持。此设备运行 iOS %@，封面将保持静止。", UIDevice.currentDevice.systemVersion]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSArray<SGOrderItem *> *sources(void) {
    return @[
        SGOrderItemMake(SGArtworkSourceSpotify, @"Spotify Canvas", @"The track's own clip"),
        SGOrderItemMake(SGArtworkSourceApple, @"Apple Music", @"The album's animated cover"),
    ];
}

SGModRow *SGArtworkSourcesRow(NSString *key, NSString *note) {
    SGModRow *row = SGPageRow(@"来源", ^UIViewController *{
        return SGOrderPage(@"Artwork sources", sources(), ^NSArray<NSString *> *{ return SGArtworkOrderFor(key); },
                           ^(NSArray<NSString *> *keys) { SGArtworkSetOrderFor(key, keys); }, note);
    });
    row.value = ^NSString *{
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *source in SGArtworkOrderFor(key)) {
            for (SGOrderItem *item in sources()) {
                if ([item.key isEqualToString:source]) [names addObject:item.name];
            }
        }
        return names.count ? [names componentsJoinedByString:@"、"] : @"无";
    };
    return row;
}

NSArray<SGModRow *> *SGAnimatedArtworkRows(void) {
    if (!SGAnimatedArtworkAvailable())
        return @[SGStatActionRow(@"动态锁屏封面", nil, ^NSString *{ return @"需要 iOS 26"; }, ^{ sayWhatIsMissing(); })];
    SGModRow *order = SGArtworkSourcesRow(SGKeyLockScreenArtworkSources,
        @"Asked top to bottom until one has a clip. Apple Music gets only the artist and album name.");
    order.visible = ^BOOL { return SGFlag(SGKeyLockScreenArtwork, YES); };
    return @[
        SGSwitchRow(@"Animated lock screen", @"锁屏控制项后的动态封面", SGKeyLockScreenArtwork),
        order,
    ];
}
