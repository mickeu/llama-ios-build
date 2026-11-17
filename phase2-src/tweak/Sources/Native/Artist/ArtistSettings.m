#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Artist.h"

UIViewController *SGArtistSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(@"照片", @[
            SGOptionRow(@"Fade into a blur", nil, SGKeyArtistPhotoFade),
        ]),
        SGSection(@"在标题栏中隐藏", @[
            SGHideRow(@"Explore (video deck)", nil, SGHideArtistExplore),
            SGHideRow(@"Follow", nil, SGHideArtistFollow),
            SGHideRow(@"More options", nil, SGHideArtistMore),
            SGHideRow(@"Shuffle", nil, SGHideArtistShuffle),
            SGHideRow(@"Verified badge", nil, SGHideArtistVerified),
            SGHideRow(@"Monthly listeners", nil, SGHideArtistListeners),
        ]),
        SGSection(@"标签页", @[
            SGHideRow(@"隐藏标签栏", nil, SGHideArtistTabBar),
        ]),
        SGNotedSection(@"在页面中隐藏", @[
            SGHideRow(@"Songs you liked", nil, SGHideArtistLikedSongs),
            SGHideRow(@"Popular", nil, SGHideArtistPopular),
            SGHideRow(@"Artist pick", nil, SGHideArtistPick),
            SGHideRow(@"Popular releases", nil, SGHideArtistReleases),
            SGHideRow(@"Featuring", nil, SGHideArtistFeaturing),
            SGHideRow(@"Music videos", nil, SGHideArtistVideos),
            SGHideRow(@"About", nil, SGHideArtistAbout),
            SGHideRow(@"Artist playlists", nil, SGHideArtistPlaylists),
            SGHideRow(@"Fans also like", nil, SGHideArtistFansAlsoLike),
            SGHideRow(@"Appears on", nil, SGHideArtistAppearsOn),
            SGHideRow(@"Discovered on", nil, SGHideArtistDiscoveredOn),
        ], @"Works only with Spotify in English."),
        SGSection(@"Spotify 原生内容", @[
            SGFlagRow(@"Share button in the header", @"ios-creator-impl.share_in_action_row_enabled_artist"),
            SGFlagRow(@"More options in the navigation bar", @"ios-creator-impl.context_menu_in_navigation_bar_enabled_artist"),
            SGFlagRow(@"Top collaborators", @"ios-creator-impl.is_top_collaborators_enabled"),
            SGFlagRow(@"Artist facts", @"ios-creator-impl.is_artist_facts_enabled"),
        ]),
    ];
    return [[SGModPage alloc] initWithTitle:@"艺人" intro:nil sections:sections footer:nil];
}
