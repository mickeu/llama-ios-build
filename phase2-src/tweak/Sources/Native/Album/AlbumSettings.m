#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(@"标题栏", @[
            SGOptionRow(@"封面背景", nil, SGKeyAlbumBackdrop),
        ]),
        SGSection(@"在标题栏中隐藏", @[
            SGHideRow(@"Explore (video deck)", nil, SGHideAlbumExplore),
            SGHideRow(@"Add to library", nil, SGHideAlbumAddTo),
            SGHideRow(@"下载", nil, SGHideAlbumDownload),
            SGHideRow(@"More options", nil, SGHideAlbumMore),
        ]),
        SGNotedSection(@"Hide on the page", @[
            SGHideRow(@"More by the artist", nil, SGHideAlbumMoreBy),
            SGHideRow(@"Related music videos", nil, SGHideAlbumVideos),
            SGHideRow(@"Concerts", nil, SGHideAlbumConcerts),
            SGHideRow(@"Merch", nil, SGHideAlbumMerch),
            SGHideRow(@"You might also like", nil, SGHideAlbumYouMightLike),
        ], @"Works only with Spotify in English."),
    ];
    return [[SGModPage alloc] initWithTitle:@"专辑" intro:nil sections:sections footer:nil];
}
