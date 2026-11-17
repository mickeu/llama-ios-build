// 免费账号的播放控制由 ads-now-playing 的遥控策略裁定：广告在播时它把上一曲、下一曲、循环、
// 顺序报成"不可用"，按钮于是变灰或按下去弹升级。这一层把那类 should…CommandBeAvailable /
// …BeEnabled 统一答可用，并把 AdsProductState 的广告状态恒答关。两者都是布尔 getter，只动
// 类型编码确认为 B16@0:8 的方法：对不上就跳过，宁可不生效，也不把返回值形状改坏。
//
// 日志走 Documents/probe.log，纯 C 写：这条路径在注入早期就跑，碰 Foundation/Swift 桥接对象
// 会把运行时带崩。
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdarg.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>
#import "Core/SGCore.h"
#import "SGProbeLog.h"

// 纯 POSIX 写日志：这条路径会在注入早期的工作线程上跑，走 Foundation 的文件接口实测会把
// Swift 运行时带崩（SIGABRT，栈上是 libswiftCore -> abort），只留 open/write/close。
void SGProbeWrite(const char *text, size_t length) {
    const char *home = getenv("HOME");
    if (!home || !length) return;
    char path[512];
    int n = snprintf(path, sizeof(path), "%s/Documents/probe.log", home);
    if (n <= 0 || (size_t)n >= sizeof(path)) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    ssize_t ignored = write(fd, text, length);
    (void)ignored;
    close(fd);
}

void SGProbeC(const char *fmt, ...) {
    if (!fmt) return;
    char buffer[512];
    va_list args;
    va_start(args, fmt);
    int n = vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    if (n <= 0) return;
    if ((size_t)n >= sizeof(buffer)) n = (int)sizeof(buffer) - 1;
    SGProbeWrite(buffer, (size_t)n);
    SGProbeWrite("\n", 1);
}

#pragma mark - transport commands

static BOOL SGAnswerYes(__unused id self, __unused SEL _cmd) { return YES; }
static BOOL SGAnswerNo(__unused id self, __unused SEL _cmd) { return NO; }

// shouldNextTrackCommandBeAvailable, shouldPreviousTrackCommandBeEnabled, … 只认这四个命令：
// 上一曲、下一曲、循环、顺序。点赞/收藏这些命令的"可用"背后要 title，一放开就撞断言
// （LockScreenRemoteLikeCommands.swift:13），跟本开关无关，不碰。
static BOOL SGCarriesCommand(SEL sel) {
    const char *name = sel_getName(sel);
    if (strncmp(name, "should", 6) != 0) return NO;
    if (!(strstr(name, "NextTrack") || strstr(name, "PreviousTrack") || strstr(name, "Repeat") || strstr(name, "Shuffle")))
        return NO;
    return strstr(name, "BeAvailable") != NULL || strstr(name, "BeEnabled") != NULL;
}

static NSUInteger SGUnlockTransport(Class cls) {
    if (!cls) return 0;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return 0;
    NSUInteger changed = 0;
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        if (!SGCarriesCommand(sel)) continue;
        const char *types = method_getTypeEncoding(methods[i]);
        if (!types || strcmp(types, "B16@0:8") != 0) continue;
        class_replaceMethod(cls, sel, (IMP)SGAnswerYes, types);
        changed++;
    }
    free(methods);
    return changed;
}

// adsEnabled / isAdsEnabled on the product state: no surface is told the account carries ads.
static NSUInteger SGForceAdsOff(Class cls) {
    if (!cls) return 0;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return 0;
    NSUInteger changed = 0;
    for (unsigned int i = 0; i < count; i++) {
        const char *name = sel_getName(method_getName(methods[i]));
        if (strcmp(name, "adsEnabled") != 0 && strcmp(name, "isAdsEnabled") != 0) continue;
        const char *types = method_getTypeEncoding(methods[i]);
        if (!types || strcmp(types, "B16@0:8") != 0) continue;
        class_replaceMethod(cls, method_getName(methods[i]), (IMP)SGAnswerNo, types);
        changed++;
    }
    free(methods);
    return changed;
}

#pragma mark - shuffle diagnostics

// 随机播放的免费限制在哪一层：这几个类里任一的布尔 getter 就是答案。只打选择器名——Swift 的
// 相对方法表上类型编码指针不可读，打它会把进程打死（已踩过）。只在注入时跑，运行期不枚举。
static NSString *const shuffleClasses[] = {
    @"_TtC40ContextualShuffle_ShuffleToggleModelImpl35ContextualShuffleDefaultPermissions",
    @"_TtC40ContextualShuffle_ShuffleToggleModelImpl30CentralizedShuffleStateHandler",
    @"_TtC40ContextualShuffle_ShuffleToggleModelImpl24ContextualShuffleService",
    @"_TtC31FreeShuffle_RecommendationsImpl47FreeShuffleRecommendationsServiceImplementation",
    @"_TtC28ContextualShuffle_UpsellImpl38ShuffleToggleUpsellModelImplementation",
};

static void SGDumpShuffleClasses(void) {
    for (size_t c = 0; c < sizeof(shuffleClasses) / sizeof(shuffleClasses[0]); c++) {
        Class cls = objc_getClass(shuffleClasses[c].UTF8String);
        if (!cls) {
            SGProbeC("SHUF class %s missing", shuffleClasses[c].UTF8String);
            continue;
        }
        SGProbeC("SHUF class %s", class_getName(cls));
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int m = 0; m < count; m++) {
            SGProbeC("SHUF   -[%s]", sel_getName(method_getName(methods[m])));
        }
        free(methods);
    }
}

#pragma mark - ad entry points

// 广告在播时谁在动：只扫类名里带 Ad 的类（几百个），输出封顶，避免启动期 IO 拖死。
// 之前一版用 class_respondsToSelector 扫全表，私有类对它假答 YES，刷了几万行，启动被掐。
static const char *adSelectors[] = {
    "startAdPlayback", "didEnterAdBreak", "adPlaybackStarted", "playAd", "isAdPlaying", "inAdBreak",
    "endAdPlayback", "endAdEarly", "skipAd",
};

static void SGDumpAdEntryPoints(void) {
    int total = objc_getClassList(NULL, 0);
    Class *all = total > 0 ? (Class *)malloc(sizeof(Class) * (size_t)total) : NULL;
    if (!all) return;
    total = objc_getClassList(all, total);
    NSUInteger lines = 0;
    for (int i = 0; i < total && lines < 200; i++) {
        const char *name = class_getName(all[i]);
        if (!name || !strstr(name, "Ad")) continue;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(all[i], &count);
        if (!methods) continue;
        BOOL named = NO;
        for (unsigned int m = 0; m < count && lines < 200; m++) {
            const char *sel = sel_getName(method_getName(methods[m]));
            for (size_t k = 0; k < sizeof(adSelectors) / sizeof(adSelectors[0]); k++) {
                if (strcmp(sel, adSelectors[k]) != 0) continue;
                if (!named) { SGProbeC("ADSEL class %s", name); named = YES; lines++; }
                SGProbeC("ADSEL   -[%s]", sel);
                lines++;
            }
        }
        free(methods);
    }
    free(all);
}

// 随机播放的闸门在哪一层：类名带 Shuffle/Player 的类里，凡选择器名含 huffle/epeat/kip 的都点出来。
// 只打名字、封顶 400 行，启动期不碰任何类型编码。
static void SGDumpShuffleEntryPoints(void) {
    int total = objc_getClassList(NULL, 0);
    Class *all = total > 0 ? (Class *)malloc(sizeof(Class) * (size_t)total) : NULL;
    if (!all) return;
    total = objc_getClassList(all, total);
    NSUInteger lines = 0;
    for (int i = 0; i < total && lines < 400; i++) {
        const char *name = class_getName(all[i]);
        if (!name || !(strstr(name, "Shuffle") || strstr(name, "Player"))) continue;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(all[i], &count);
        if (!methods) continue;
        BOOL named = NO;
        for (unsigned int m = 0; m < count && lines < 400; m++) {
            const char *sel = sel_getName(method_getName(methods[m]));
            if (!(strstr(sel, "huffle") || strstr(sel, "epeat") || strstr(sel, "kip"))) continue;
            if (!named) { SGProbeC("SHUFX class %s", name); named = YES; lines++; }
            SGProbeC("SHUFX   -[%s]", sel);
            lines++;
        }
        free(methods);
    }
    free(all);
}

#pragma mark - player restrictions

// 免费账号的"不能"到底在哪：客户端把限制做成一组 disallow… 布尔 getter（SPTPlayerRestrictions、
// StatefulPlayerPlaybackControlsImplementation）与 shuffleTogglingIsEnabled 这类开关。全部答
// 允许，随机按钮才点得灭、循环与跳曲才听话。只动无参、返回 BOOL 的方法。
static BOOL SGIsDisallowSelector(SEL sel) {
    return strncmp(sel_getName(sel), "disallow", 8) == 0;
}

static BOOL SGIsAllowToggleSelector(SEL sel) {
    const char *name = sel_getName(sel);
    if (strcmp(name, "shuffleTogglingIsEnabled") == 0) return YES;
    if (strcmp(name, "isSmartShuffleAllowed") == 0) return YES;
    // check…CanBeToggled…：智能随机的可切换判定，答"能"，按钮才不会点一次闪一次。
    return strstr(name, "CanBeToggled") != NULL;
}

// 会拦下切换的推销开关与"免费随机镜片"：答否。
static BOOL SGIsUpsellSelector(SEL sel) {
    const char *name = sel_getName(sel);
    return strcmp(name, "shuffleButtonUpsellEnabled") == 0
        || strstr(name, "smartShuffleLensEnabled") != NULL
        || strcmp(name, "unbrandedSmartShuffleEnabled") == 0;
}

// 广告可跳过的延迟：答 0，插播时立刻能跳过。
static void SGNoteAdTrack(void) {
    static int noted;
    if (noted >= 5) return;
    noted++;
    SGProbeC("ADTRACK skippable delay requested (count=%d)", noted);
}

static double SGAnswerZeroDouble(__unused id self, __unused SEL _cmd) { SGNoteAdTrack(); return 0.0; }
static long long SGAnswerZeroInteger(__unused id self, __unused SEL _cmd) { SGNoteAdTrack(); return 0; }

static NSUInteger SGUnlockAdSkipDelay(Class cls) {
    if (!cls) return 0;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return 0;
    NSUInteger changed = 0;
    for (unsigned int i = 0; i < count; i++) {
        if (strcmp(sel_getName(method_getName(methods[i])), "spt_skippableAdDelay") != 0) continue;
        const char *types = method_getTypeEncoding(methods[i]);
        if (!types) continue;
        if (strcmp(types, "d16@0:8") == 0) {
            class_replaceMethod(cls, method_getName(methods[i]), (IMP)SGAnswerZeroDouble, types);
            changed++;
        } else if (strcmp(types, "q16@0:8") == 0) {
            class_replaceMethod(cls, method_getName(methods[i]), (IMP)SGAnswerZeroInteger, types);
            changed++;
        }
    }
    free(methods);
    return changed;
}

static NSUInteger SGUnlockRestrictions(Class cls) {
    if (!cls) return 0;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return 0;
    NSUInteger changed = 0;
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        BOOL disallow = SGIsDisallowSelector(sel) || SGIsUpsellSelector(sel);
        BOOL allow = SGIsAllowToggleSelector(sel);
        if (!disallow && !allow) continue;
        const char *types = method_getTypeEncoding(methods[i]);
        if (!types || strcmp(types, "B16@0:8") != 0) continue;
        class_replaceMethod(cls, sel, (IMP)(disallow ? SGAnswerNo : SGAnswerYes), types);
        changed++;
    }
    free(methods);
    return changed;
}

#pragma mark - ad track detection

// SPTPlayerTrack 上的广告标记：spt_adId 非空就是一条插播广告。这里只做观测，不改返回值——
// 目的是在真机上确认广告究竟从哪条路径进来（spt_skippableAdDelay 那次没有触发，说明不一定是它）。
static NSString *(*sgOriginalAdId)(id, SEL);

static NSString *SGAdId(id self, SEL _cmd) {
    NSString *value = sgOriginalAdId ? sgOriginalAdId(self, _cmd) : nil;
    static int noted;
    if (value.length && noted < 5) {
        noted++;
        SGProbeC("ADTRACK spt_adId non-nil (count=%d)", noted);
    }
    return value;
}

static void SGInstallAdTrackProbe(void) {
    Class cls = objc_getClass("SPTPlayerTrack");
    if (!cls) {
        SGProbeC("ADTRACK SPTPlayerTrack missing");
        return;
    }
    Method method = class_getInstanceMethod(cls, sel_registerName("spt_adId"));
    if (!method) {
        SGProbeC("ADTRACK spt_adId missing");
        return;
    }
    const char *types = method_getTypeEncoding(method);
    if (!types || strcmp(types, "@16@0:8") != 0) {
        SGProbeC("ADTRACK spt_adId unexpected encoding, left alone");
        return;
    }
    sgOriginalAdId = (NSString *(*)(id, SEL))method_getImplementation(method);
    class_replaceMethod(cls, sel_registerName("spt_adId"), (IMP)SGAdId, types);
    SGProbeC("ADTRACK spt_adId probe installed");
}

#pragma mark - install

// 只动广告与默认策略，且只动上一曲/下一曲/循环/顺序这四个命令。
static void SGApplyUnlock(BOOL verbose) {
    NSUInteger policies = 0, ads = 0, limits = 0;
    int total = objc_getClassList(NULL, 0);
    Class *all = total > 0 ? (Class *)malloc(sizeof(Class) * (size_t)total) : NULL;
    if (all) {
        total = objc_getClassList(all, total);
        for (int i = 0; i < total; i++) {
            const char *name = class_getName(all[i]);
            if (!name) continue;
            if (strstr(name, "RemoteControlPolicy")
                && (strstr(name, "Ads") || strstr(name, "Default") || strstr(name, "Base"))) {
                NSUInteger n = SGUnlockTransport(all[i]);
                if (n && verbose) SGProbeC("unlocked %lu transport gates on %s", (unsigned long)n, name);
                policies += n;
            }
            if (strstr(name, "PlayerRestrictions") || strstr(name, "StatefulPlayer")
                || strstr(name, "ShuffleToggleModel") || strstr(name, "SmartShuffle")
                || strstr(name, "ShuffleToggleUpsellModel") || strstr(name, "FreeShuffle")) {
                NSUInteger n = SGUnlockRestrictions(all[i]);
                if (n && verbose) SGProbeC("unlocked %lu restrictions on %s", (unsigned long)n, name);
                limits += n;
            }
            if (strstr(name, "SPTPlayerTrack")) {
                NSUInteger n = SGUnlockAdSkipDelay(all[i]);
                if (n && verbose) SGProbeC("ad skip delay zeroed on %s", name);
                limits += n;
            }
            if (strstr(name, "ProductState")) {
                NSUInteger n = SGForceAdsOff(all[i]);
                if (n && verbose) SGProbeC("forced %lu ads getters off on %s", (unsigned long)n, name);
                ads += n;
            }
        }
        free(all);
    }
    if (verbose) {
        SGProbeC("playback unlock: transport=%lu ads=%lu limits=%lu", (unsigned long)policies, (unsigned long)ads, (unsigned long)limits);
    }
}

__attribute__((constructor)) static void SGInstallPlaybackUnlock(void) {
    // 只跑这一次。曾经在十二/二十秒后再跑一遍枚举，两轮实测都在 dispatch 回调里被 Swift 运行时
    // abort 打死（栈：libswiftCore -> abort，调用者落在枚举处）：运行期遍历类表会 realize 所有
    // Swift 类，时机与线程都不受控。解锁所需的那几个策略类在注入时已注册，一次就够。
    SGApplyUnlock(YES);
    SGDumpShuffleClasses();
    SGInstallAdTrackProbe();
    SGDumpAdEntryPoints();
    SGDumpShuffleEntryPoints();
}
