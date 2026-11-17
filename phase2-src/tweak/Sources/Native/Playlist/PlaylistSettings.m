#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGPlaylistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"播放列表" intro:nil sections:@[
        SGSection(@"标题栏", @[
            SGOptionRow(@"封面背景", nil, SGKeyPlaylistBackdrop),
        ]),
        SGSection(@"在播放列表标题中隐藏", @[
            SGHideRow(@"Cover artwork", nil, SGHidePlaylistArtwork),
            SGHideRow(@"Description", nil, SGHidePlaylistDescription),
            SGHideRow(@"Creator and collaborators", nil, SGHidePlaylistCreator),
            SGHideRow(@"Length and saves", nil, SGHidePlaylistLength),
        ]),
        SGSection(@"隐藏播放列表按钮", @[
            SGHideRow(@"Video", nil, SGHidePlaylistVideo),
            SGHideRow(@"Add to library", nil, SGHidePlaylistAddTo),
            SGHideRow(@"下载", nil, SGHidePlaylistDownload),
            SGHideRow(@"Share", nil, SGHidePlaylistShare),
            SGHideRow(@"More", nil, SGHidePlaylistMore),
        ]),
        SGSection(@"在曲目上方隐藏", @[
            SGHideRow(@"Curation pills", nil, SGHidePlaylistPills),
            SGHideRow(@"Find and sort bar", nil, SGHidePlaylistFind),
        ]),
    ] footer:nil];
}
