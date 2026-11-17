// Mod Settings > Karaoke, in the redesign (App/ModSettings.x puts its row on the main page): Sing's switch and
// its voice model. The switch puts the microphone in the player's lyrics and takes it away again at once; off, Sing
// does no work at all. The model row reads out where the download is and moves along with it, over a bar
// while it runs, and the row under it is what can be done next: download it, stop the download, or remove
// the model. Below iOS 27, where the separator cannot run, the section is one row saying so.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Sing/SGSingModel.h"
#import "Sing.h"

// The model's size as the footer and the prompts say it, to the nearest ten megabytes.
static NSString *aboutSize(void) {
    return [NSString stringWithFormat:@"约 %lld MB", ((SGSingModelSize() >> 20) + 5) / 10 * 10];
}

static NSString *footer(void) {
    return [NSString stringWithFormat:@"Sing 会降低正在播放歌曲的人声，让你可通过歌词页面中的麦克风跟唱。"
            "仅支持 iOS 27。人声模型（%@）只需下载一次，并且仅在此 iPhone 上运行。"
            "开关和下载会立即生效。", aboutSize()];
}

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSString *modelStatus(void) {
    int64_t received = SGSingModelReceived(), size = SGSingModelSize();
    switch (SGSingModelCurrentState()) {
        case SGSingModelInstalled: return [@"已下载 · " stringByAppendingString:SGSingModelBytesText(size)];
        case SGSingModelChecking: return @"正在检查…";
        case SGSingModelDownloading:
            return [NSString stringWithFormat:@"正在下载 %lld%% · %lld/%@", received * 100 / size,
                    (received + (1ll << 19)) >> 20, SGSingModelBytesText(size)];
        case SGSingModelMissing:
            if (SGSingModelFailure()) return @"下载失败";
            if (received > 0) return [NSString stringWithFormat:@"已暂停 · %lld/%@", (received + (1ll << 19)) >> 20, SGSingModelBytesText(size)];
            return @"未下载";
    }
    return nil;
}

// A tap on the model row says what its value is short for.
static void explainModel(void) {
    NSString *failure = SGSingModelFailure();
    switch (SGSingModelCurrentState()) {
        case SGSingModelInstalled:
            tell(@"人声模型", [NSString stringWithFormat:@"它在此 iPhone 上占用 %@。移除它可释放空间；没有该模型则无法使用 Sing。",
                                  SGSingModelBytesText(SGSingModelSize())]);
            break;
        case SGSingModelMissing:
            tell(failure ? @"下载失败" : @"人声模型",
                 failure ? [failure stringByAppendingString:@" 下载会从中断位置继续。"]
                         : [NSString stringWithFormat:@"Sing 需要先下载人声模型（%@），歌词中的麦克风才会显示。", aboutSize()]);
            break;
        default:
            tell(@"人声模型", @"即使 Spotify 在后台，下载仍会继续。下载完成后，歌词中会显示 Sing 的麦克风。");
    }
}

// Enough room first, then the network: nothing leaves on cellular without a yes.
static void startDownload(void) {
    NSString *space = SGSingModelSpaceProblem();
    if (space) { tell(@"储存空间不足", space); return; }
    SGSingModelCheckNetwork(^(SGSingModelNetwork network) {
        if (network == SGSingModelOffline) {
            tell(@"没有互联网连接", @"请连接 Wi‑Fi 以下载 Sing 的人声模型。");
        } else if (network == SGSingModelMetered) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"要使用蜂窝网络下载吗？"
                message:[NSString stringWithFormat:@"此 iPhone 未连接 Wi‑Fi，Sing 的人声模型大小为 %@。", aboutSize()]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"下载" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                SGSingModelDownload(YES);
            }]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        } else {
            SGSingModelDownload(NO);
        }
    });
}

static void confirmRemove(void) {
    BOOL installed = SGSingModelCurrentState() == SGSingModelInstalled;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"移除人声模型？"
        message:installed ? [NSString stringWithFormat:@"在重新下载前，Sing 将不可用（%@）。", aboutSize()]
                          : [NSString stringWithFormat:@"目前已下载的 %@ 将被删除，下次下载会从头开始。",
                             SGSingModelBytesText(SGSingModelReceived())]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        SGSingModelRemove();
    }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Below iOS 27 the switch is a row saying what is missing.
static SGModRow *unavailableRow(void) {
    return SGStatActionRow(@"Sing", nil, ^NSString *{ return @"需要 iOS 27"; }, ^{
        tell(@"Sing", [NSString stringWithFormat:@"Sing 会通过人声模型在此 iPhone 上分离歌曲人声，该功能需要 iOS 27。 "
                       "This iPhone runs iOS %@.", UIDevice.currentDevice.systemVersion]);
    });
}

static SGModSection *karaokeSection(void) {
    if (!SGSingSupported()) return SGNotedSection(@"卡拉 OK", @[unavailableRow()], footer());
    SGModRow *sing = SGOptionRow(@"Sing", @"歌词中的麦克风", SGRKeySing);
    sing.changed = ^(__unused BOOL on) { SGRSingApplySwitch(); };

    SGModRow *model = SGStatActionRow(@"人声模型", nil, ^NSString *{ return modelStatus(); }, ^{ explainModel(); });
    model.progress = ^double {
        return SGSingModelCurrentState() == SGSingModelDownloading ? (double)SGSingModelReceived() / SGSingModelSize() : -1;
    };
    model.refreshOn = SGSingModelDidChangeNotification;

    SGModRow *download = SGActionRow(@"下载人声模型", nil, ^{ startDownload(); });
    download.visible = ^BOOL { return SGSingModelCurrentState() == SGSingModelMissing; };
    SGModRow *cancel = SGActionRow(@"取消下载", nil, ^{ SGSingModelCancel(); });
    cancel.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelDownloading || state == SGSingModelChecking;
    };
    // Removing also takes what a stopped download kept, which can be most of the model.
    SGModRow *remove = SGActionRow(@"移除人声模型", nil, ^{ confirmRemove(); });
    remove.color = SGRed();
    remove.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelInstalled || (state == SGSingModelMissing && SGSingModelReceived() > 0);
    };
    return SGNotedSection(@"卡拉 OK", @[sing, model, download, cancel, remove], footer());
}

UIViewController *SGRKaraokeSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"卡拉 OK" intro:nil sections:@[karaokeSection()] footer:nil];
}

// Beside the main page's row: what Sing would do now, or how far its model has come.
NSString *SGRKaraokeSummary(void) {
    if (!SGSingSupported()) return @"Needs iOS 27";
    SGSingModelState state = SGSingModelCurrentState();
    if (state == SGSingModelDownloading) return [NSString stringWithFormat:@"%lld %%", SGSingModelReceived() * 100 / SGSingModelSize()];
    if (state == SGSingModelChecking) return @"正在检查…";
    if (!SGFlag(SGRKeySing, NO)) return @"关闭";
    return state == SGSingModelInstalled ? @"开启" : @"无模型";
}
