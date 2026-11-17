// 广告与 Premium 页：上游 AdBlockSettings.m 的页面，按本树的接口重写。
//
// 与上游的差别：
//  * 上游页面由 SGPrivacySection() / SGPrivacyCountersSection() 拼成，这两个函数在本树已经不存在
//    （Privacy.h 只剩 SGPrivacySettingsPage()）。这里不再造一套隐私开关，改为在页面里放一行指向
//    原来的隐私页 —— 复用它已有的入口，旧入口一个不少，也不引用不存在的 API。
//  * 开关全部中文，"模拟 Premium"仍是要用户自己打开、打开前先说清风险的一项，不是启动弹窗。
//  * 计数按 AdBlock.m 的标签显示，"改写生效/无需改写/解析失败/超限透传"分开：命中不等于改写成功。
#import "Settings/SGModPage.h"
#import "AdBlock.h"
#import "Shared/Privacy/Privacy.h"

// 广告与推销的 flag 页：这里列的是开关打开时被强制关掉的 flag，行会被锁定。
static UIViewController *adFlagsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"广告与推销开关" intro:SGRestartNote sections:@[
        SGNotedSection(@"广告", @[
            SGKillRow(@"阻止打开应用时的广告", @"ios-feature-adonappopen.enabled"),
            SGKillRow(@"阻止它的推广卡片", @"ios-feature-adonappopen.cta_card_enabled"),
        ], @"“隐藏广告”打开时这些行被锁定。"),
        SGNotedSection(@"推销", @[
            SGKillRow(@"隐藏随机播放的推销开关", @"ios-feature-shuffletoggleupsell.is_enabled_pt2"),
            SGKillRow(@"隐藏视频播放器的随机播放推销", @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled"),
        ], @"“隐藏升级推销”打开时这些行被锁定。"),
    ] footer:nil];
}

static SGModSection *countersSection(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGAdBlockLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{
            return @(SGAdBlockCount(label)).stringValue;
        })];
    }
    [counts addObject:SGStatRow(@"总计", ^NSString *{
        return @(SGAdBlockCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(@"重置计数", nil, ^{ SGResetAdBlock(); })];
    return SGSection(@"已经拦下与改写的", counts);
}

// 开关在前，计数在后，免得计数把设置埋了。
UIViewController *SGAdsSettingsPage(void) {
    SGModRow *fakePremium = SGOptionRow(@"模拟 Premium", @"改写账号状态与远控配置；仅免费账号需要", SGKeyFakePremium);
    fakePremium.warning = SGFakePremiumWarning;

    return [[SGModPage alloc] initWithTitle:@"广告与 Premium" intro:SGRestartNote sections:@[
        SGNotedSection(@"广告", @[
            SGWithSymbol(SGOptionRow(@"隐藏广告", @"广告服务、页面组件与信息流里的广告", SGKeyHideAds), @"speaker.slash"),
            SGWithSymbol(SGOptionRow(@"隐藏升级推销", @"Premium 促销弹窗、横幅与卡片", SGKeyHideUpsells), @"hand.raised"),
            SGWithSymbol(SGPageRow(@"广告与推销开关", ^UIViewController *{ return adFlagsPage(); }), @"flag"),
        ], @"歌曲之间的音频广告要“模拟 Premium”才会消失。"),
        SGNotedSection(@"Premium", @[
            SGWithSymbol(fakePremium, @"crown"),
        ], @"默认关闭，打开前会先说明风险。"),
        SGSection(@"隐私", @[
            SGWithSymbol(SGPageRow(@"隐私与界面精简", ^UIViewController *{ return SGPrivacySettingsPage(); }), @"shield.lefthalf.filled"),
        ]),
        countersSection(),
    ] footer:nil];
}
