#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/Player/PlayerSettings.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Kit/SGRAccent.h"

NSString *const SGRedesignedUIInfo = @"spoti.pw 的最新界面，风格更接近 Apple Music。它与旧版界面的设置不兼容。\n\n旧版界面提供更多自定义选项，但仍保留 Spotify 的风格。";

void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
    if (!SGRedesignTested()) SGSetEnabled(SGKeyRedesignUntested, on);
}

NSString *SGRedesignUntestedWarning(void) {
    return [NSString stringWithFormat:@"新版界面为 iOS 26 设计，尚未在 iOS %@ 上测试。可能出现错误或卡死；若 Spotify 无法打开，请删除后重新安装。", UIDevice.currentDevice.systemVersion];
}

// The whole look changes hands at launch, so the switch asks for the restart straight away rather than
// leaving Spotify half in the old look.
static void offerRestart(BOOL on) {
    NSString *restart = on ? @"新版界面会在下次启动 Spotify 时生效。Spotify 将立即关闭，请重新打开以查看效果。" : @"Spotify 原本的界面会在下次启动时恢复。Spotify 将立即关闭，请重新打开以查看效果。";
    BOOL untested = on && !SGRedesignTested();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:untested ? @"未在此 iOS 版本测试" : @"重启 Spotify"
        message:untested ? [NSString stringWithFormat:@"%@\n\n%@", SGRedesignUntestedWarning(), restart] : restart
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"以后再说" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

SGModSection *SGAppearanceSection(void) {
    SGModRow *redesign = SGOptionRow(@"新版界面", nil, SGKeyRedesign);
    redesign.glows = YES;
    redesign.info = SGRedesignedUIInfo;
    redesign.changed = ^(BOOL on) {
        SGSetRedesignedUI(on);
        offerRestart(on);
    };
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObject:SGWithSymbol(redesign, @"sparkles")];
    [rows addObjectsFromArray:SGRedesignedUIStored() ? SGRAppearanceRows() : SGNativeAppearanceRows()];
    return SGNotedSection(@"外观", rows, @"重启 Spotify 后生效。");
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

// Pronunciation, translation, word sweeping and line meanings exist only in the redesign's lyrics.
UIViewController *SGLyricsSettingsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObject:SGLockScreenLyricsRow()];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGLyricsSourcesSection(redesigned)];
    if (redesigned) {
        [sections addObject:SGSection(@"显示", @[SGLyricsWordTimingRow(), SGRLyricsTextSizesRow(), SGLyricsTranslationLanguageRow(), SGLyricsMeaningsRow()])];
    }
    [sections addObject:SGSection(nil, more)];
    return [[SGModPage alloc] initWithTitle:@"歌词" intro:SGRestartNote sections:sections footer:nil];
}

UIViewController *SGPlayerSettingsPage(void) {
    SGModRow *blocked = SGPageRow(@"已屏蔽艺人", ^UIViewController *{ return SGArtistBlockSettingsPage(); });
    blocked.value = ^NSString *{
        return SGFlag(SGKeyArtistBlock, NO) ? @(SGBlockedArtists().count).stringValue : @"关闭";
    };
    BOOL native = !SGRedesignedUIStored();

    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[
        SGWithSymbol(SGPageRow(@"手势", ^UIViewController *{ return SGGesturesSettingsPage(); }), @"hand.tap"),
        SGWithSymbol(blocked, @"person.crop.circle.badge.xmark"),
    ])];
    NSMutableArray<SGModRow *> *pages = [NSMutableArray array];
    if (native) {
        [pages addObject:SGWithSymbol(SGPageRow(@"正在播放栏", ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
        [pages addObject:SGWithSymbol(SGPageRow(@"播放队列与设备", ^UIViewController *{ return SGQueueSettingsPage(); }), @"text.line.first.and.arrowtriangle.forward")];
    }
    [pages addObject:SGWithSymbol(SGPageRow(@"锁屏小组件", ^UIViewController *{ return SGLockScreenWidgetPage(); }), @"lock")];
    [sections addObject:SGSection(nil, pages)];
    [sections addObjectsFromArray:native ? SGNativePlayerScreenSections() : SGRNowPlayingSections()];
    // Vibrations hook Spotify's own controls and its audio, so they answer under either look.
    [sections addObjectsFromArray:SGVibrationsSections()];

    return [[SGModPage alloc] initWithTitle:@"播放器" intro:SGRestartNote sections:sections footer:nil];
}
