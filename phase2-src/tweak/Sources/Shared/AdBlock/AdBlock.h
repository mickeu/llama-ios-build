// 上游 spoti.pw 0.21.1 的 AdBlock 层（EeveeSpotify 的移植）搬到本插件：三个开关、广告与推销的
// flag forcer、响应改写（Premium.m 改 UCS，Feeds.m 删信息流里的广告段）、计数，以及显示它们的
// 设置页。搜索视频与社交推荐两个开关仍归 Shared/Privacy：键在 Privacy.h，forcer 在 Clutter.m，
// 这里既不重复定义键，也不再注册第二份同键 forcer。
//
// 开关一律"默认关"，打开才做事：SGHidden() 读的正是这个语义。改写函数是纯离线的：给字节，
// 回字节或 nil，不认识就交还原样，不在这里做任何网络或 UI 动作。
#import <UIKit/UIKit.h>

#define SGKeyHideAds @"spotifyglass.adblock.ads"
#define SGKeyHideUpsells @"spotifyglass.adblock.upsells"
#define SGKeyFakePremium @"spotifyglass.adblock.premium"

// 打开"模拟 Premium"之前页面会先说的话（用户在弹窗里确认后才写入开关）。
extern NSString *const SGFakePremiumWarning;

// "隐藏广告"/"隐藏升级推销"打开时，这个 flag 被强制为 NO；Flags.x 与 flag 行都问这里。
BOOL SGAdBlockForcesFlagOff(NSString *key);

// 计数的名字，页面按 SGAdBlockLabels() 的顺序显示。前三组是"拦了什么"，后四组是"改写的结果"：
// 命中不等于改写成功，所以生效/无需/失败分开计，另有超限透传。
extern NSString *const SGAdCountServices;     // 广告服务
extern NSString *const SGAdCountUpsells;      // 推销服务
extern NSString *const SGAdCountPopups;       // 弹窗
extern NSString *const SGAdCountComponents;   // 页面组件
extern NSString *const SGAdCountSections;     // 信息流区块
extern NSString *const SGAdCountRequests;     // 请求
extern NSString *const SGAdCountRewritten;    // 改写生效
extern NSString *const SGAdCountUnchanged;    // 无需改写
extern NSString *const SGAdCountFailed;       // 解析失败
extern NSString *const SGAdCountOversize;     // 超限透传

void SGAdBlockCountOne(NSString *label);
NSArray<NSString *> *SGAdBlockLabels(void);
NSUInteger SGAdBlockCount(NSString *label);   // nil 为总计
void SGResetAdBlock(void);

// 一次改写的结果。解析失败与"解析成功但没有可改的"必须分开：日志里"命中"不等于改写成功。
typedef NS_ENUM(NSInteger, SGBodyPatch) {
    SGBodyPatchFailed = 0,   // 字节不是预期的消息，或路径上的字段缺失
    SGBodyPatchUnchanged,    // 解析成功，原样返回
    SGBodyPatchChanged,
};

// Premium.m：v1/customize 的 body，或包着同一个 UcsResponse 的 bootstrap 消息，改写成 Premium
// 账号的。nil 表示字节不认识（调用方原样放行）。
NSData *SGPatchCustomize(NSData *body);
NSData *SGPatchAttributePayload(NSData *body);
NSData *SGPatchBootstrap(NSData *body);

// Feeds.m：browsita / casita 信息流删掉广告段后的 body；outcome 说出这次是改成了、没改还是读不懂。
NSData *SGStripFeed(NSData *body, SGBodyPatch *outcome);

// 广告与 Premium 页：三个开关、广告/推销 flag 页、隐私页入口、计数。
UIViewController *SGAdsSettingsPage(void);
