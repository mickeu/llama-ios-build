#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(@"标题栏", @[
            SGOptionRow(@"封面背景", nil, SGKeyAlbumBackdrop),
        ]),
        SGSection(@"在标题栏中隐藏", @[
            SGHideRow(@"探索（视频墙）", nil, SGHideAlbumExplore),
            SGHideRow(@"添加到音乐库", nil, SGHideAlbumAddTo),
            SGHideRow(@"下载", nil, SGHideAlbumDownload),
            SGHideRow(@"更多选项", nil, SGHideAlbumMore),
        ]),
        SGNotedSection(@"在页面中隐藏", @[
            SGHideRow(@"该艺人的更多内容", nil, SGHideAlbumMoreBy),
            SGHideRow(@"相关音乐视频", nil, SGHideAlbumVideos),
            SGHideRow(@"演唱会", nil, SGHideAlbumConcerts),
            SGHideRow(@"周边商品", nil, SGHideAlbumMerch),
            SGHideRow(@"你可能也喜欢", nil, SGHideAlbumYouMightLike),
        ], @"Works only with Spotify in English."),
    ];
    return [[SGModPage alloc] initWithTitle:@"专辑" intro:nil sections:sections footer:nil];
}
