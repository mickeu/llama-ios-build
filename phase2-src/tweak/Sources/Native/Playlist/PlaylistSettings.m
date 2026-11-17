#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGPlaylistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"播放列表" intro:nil sections:@[
        SGSection(@"标题栏", @[
            SGOptionRow(@"封面背景", nil, SGKeyPlaylistBackdrop),
        ]),
        SGSection(@"在播放列表标题中隐藏", @[
            SGHideRow(@"封面", nil, SGHidePlaylistArtwork),
            SGHideRow(@"简介", nil, SGHidePlaylistDescription),
            SGHideRow(@"创建者与合作者", nil, SGHidePlaylistCreator),
            SGHideRow(@"时长与收藏", nil, SGHidePlaylistLength),
        ]),
        SGSection(@"隐藏播放列表按钮", @[
            SGHideRow(@"视频", nil, SGHidePlaylistVideo),
            SGHideRow(@"添加到音乐库", nil, SGHidePlaylistAddTo),
            SGHideRow(@"下载", nil, SGHidePlaylistDownload),
            SGHideRow(@"分享", nil, SGHidePlaylistShare),
            SGHideRow(@"更多", nil, SGHidePlaylistMore),
        ]),
        SGSection(@"在曲目上方隐藏", @[
            SGHideRow(@"策划标签", nil, SGHidePlaylistPills),
            SGHideRow(@"查找与排序栏", nil, SGHidePlaylistFind),
        ]),
    ] footer:nil];
}
