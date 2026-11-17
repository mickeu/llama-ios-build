#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGRAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"标题栏", @[
            SGSwitchRow(@"动态封面", @"来自 Apple Music（专辑有动态封面时）", SGRKeyAnimatedCovers),
        ], @"Apple Music 仅会获得艺人名和专辑名。低数据模式或低电量模式下不会下载任何内容。"),
    ];
    return [[SGModPage alloc] initWithTitle:@"专辑" intro:nil sections:sections footer:nil];
}
