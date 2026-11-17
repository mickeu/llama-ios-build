#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGRAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"标题栏", @[
            SGSwitchRow(@"动态封面", @"来自 Apple Music（专辑有动态封面时）", SGRKeyAnimatedCovers),
        ], @"Apple Music gets only the artist and album name. Nothing is downloaded in Low Data or Low Power Mode."),
    ];
    return [[SGModPage alloc] initWithTitle:@"专辑" intro:nil sections:sections footer:nil];
}
