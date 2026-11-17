// The Lyrics page's parts; App/Pages.m assembles the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Lyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

SGModSection *SGLyricsSourcesSection(BOOL namingSource) {
    SGModRow *sources = SGPageRow(@"来源", ^UIViewController *{ return SGLyricsSourcesPage(); });
    sources.value = ^NSString *{
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *key in SGLyricsOrder()) [names addObject:SGLyricsProviderFor(key).name];
        return names.count ? [names componentsJoinedByString:@", "] : @"关闭";
    };
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObjects:sources,
        SGOptionRow(@"为所有曲目提供歌词", @"即使 Spotify 没有也尝试", SGKeyLyricsAllTracks), nil];
    if (namingSource) [rows addObject:SGOptionRow(@"显示来源", nil, SGKeyLyricsCredit)];
    if (!SGLyricsEeveeReplaces()) return SGSection(@"来源", rows);
    return SGNotedSection(@"来源", rows, @"EeveeSpotify is replacing lyrics, so these sources stay off. To use them, "
                          "turn on Do Not Replace Lyrics in EeveeSpotify's lyrics settings and restart Spotify.");
}

SGModRow *SGLockScreenLyricsRow(void) {
    return SGOptionRow(@"锁屏歌词", @"用当前歌词行替代艺人名称", SGKeyLockScreenLyrics);
}

SGModRow *SGLyricsTranslationLanguageRow(void) {
    SGModRow *row = SGChoiceRow(@"翻译语言", nil, SGKeyLyricsTranslationLanguage, SGLyricsTranslationLanguageNames(), 0);
    row.choiceFooter = @"仅在歌词附带翻译时使用。“任意”会显示第一个可用翻译。";
    return row;
}

// Only the redesign's lyrics view sweeps words.
SGModRow *SGLyricsWordTimingRow(void) {
    return SGOptionRow(@"模拟逐词时间轴", nil, SGKeyLyricsSimulateWords);
}
