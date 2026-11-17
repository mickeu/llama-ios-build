#import "Settings/SGModPage.h"
#import "Settings/SGOrderPage.h"
#import "LyricsSources.h"

static NSString *const kSpicyDashboard = @"https://developers.spicylyrics.org/dashboard";

static SGModSection *spicySection(void) {
    SGModRow *key = SGTextRow(@"Spicy Lyrics 密钥",
        @"粘贴你在 Spicy Lyrics 开发者平台创建的应用公开密钥（sl_pk_…）。", @"sl_pk_…",
        ^NSString *{
            NSString *shown = SGSpicyLyricsKeyShown();
            return !shown ? @"未设置" : SGSpicyLyricsProblem() ? @"已被拒绝" : shown;
        },
        ^NSString *(NSString *text) { return SGSpicyLyricsSetKey(text); });
    key.refreshOn = SGSpicyLyricsKeyDidChangeNotification;
    SGModSection *section = SGNotedSection(@"Spicy Lyrics", @[key],
        @"Spicy Lyrics 需要使用你自己的免费密钥。在其开发者平台注册、创建应用，开启客户端访问并允许无 Origin 请求头，然后把公开密钥粘贴到这里。歌词会按条款要求显示同步来源。");
    section.footerLink = kSpicyDashboard;
    return section;
}

UIViewController *SGLyricsSourcesPage(void) {
    NSMutableArray<SGOrderItem *> *items = [NSMutableArray array];
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        SGOrderItem *item = SGOrderItemMake(provider.key, provider.name, provider.detail);
        if ([provider.key isEqualToString:@"spicylyrics"]) item.problem = ^NSString *{ return SGSpicyLyricsProblem(); };
        [items addObject:item];
    }
    return SGOrderPageWithSection(@"歌词来源", items, ^NSArray<NSString *> *{ return SGLyricsOrder(); },
                                  ^(NSArray<NSString *> *order) { SGLyricsSetOrder(order); },
                                  @"将按从上到下的顺序尝试，直到找到含逐词时间轴的来源。来源仅会获得曲目信息，绝不会获得你的账号信息。", spicySection());
}
