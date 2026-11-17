// Spotify's responses on their way in, through the URLSession delegates it reads them by:
// SPTDataLoaderService for most of spclient, HttpClientURLSession for what some regions route the
// other way. A request for an ad is answered empty. With Spoof Premium on, the bootstrap
// and customize bodies are rewritten by Premium.m before the client sees them, the entitlement
// checks the server would use to undo the state are answered as if they succeeded, and past the
// first thirty seconds the re-fetches that could bring the real state back are cancelled before they
// leave. Feeds go through Feeds.m. Everything here is EeveeSpotify's, less its Ably hooks, which it
// does not turn on for 9.1 either.
//
// —— 本树适配（逐条对应 Docs/upstream-adblock-port.md）——
// 1. 目标 host 边界：路径规则只在 spotify.com / *.spotify.com 上生效，广告域名单独一张小表按
//    域名（含子域）空答。不再对任意 host 做 /marketing/、/campaign/ 之类的泛匹配，也不整体拦
//    pam/gabo/pendragon：只有下游明确列出的那些路径、且在 Spotify 自己的 host 上才动。
// 2. 不碰注销：上游 isLogout 把 logout/sign-out/session-purge/token-revoke/auth-expire/deletetoken
//    一并答成功，那会挡掉用户自己按的"退出登录"。这里只保留服务器侧的纠错/校验端点
//    （product-state、melody…check、license…check），凭据撤销类请求一律放行。
// 3. 缓冲上限 2 MiB：超限时把已累计的原始 body 一次性回投给下游，本块与后续块原样透传，绝不丢块；
//    这次响应不再改写。
// 4. scrollsita 不做 feed 改写：那是歌词层（Shared/LyricsSources/LyricsHook.x）持有并改写 card
//    list 的路径。本轮让它原样走歌词链，只改 browsita / casita。
// 5. 计数分开：改写生效 / 无需改写 / 解析失败 / 超限透传。日志命中不算改写成功。
// 6. 日志只写类别、字节数、成败：不写完整 URL、host、账号、token、曲目名。
#import "Core/SGCore.h"
#import "AdBlock.h"
#import "proto/SGProtoRewrite.h"
#import "SGProbeLog.h"

// 一个被扣住的响应最多攒这么多字节，超过就放弃改写、原样放行。
static const NSUInteger kBufferLimit = 2 * 1024 * 1024;

static BOOL ads, premium;
static NSDate *started;
static NSObject *cacheLock;
static NSData *cachedCustomize;   // the last rewritten customize body, for a 304 and the re-fetches
static char kBufferKey, kOverflowKey, kServedKey, kPassKey, kKindKey;

typedef NS_ENUM(NSInteger, SGNet) { SGNetPass, SGNetBlock, SGNetPatch };

static NSTimeInterval elapsed(void) {
    return -started.timeIntervalSinceNow;
}

static BOOL has(NSString *text, NSString *needle) {
    return [text containsString:needle];
}

#pragma mark - what a URL is

// Spotify's own hosts and nothing else: spclient, ap, apresolve, ads… all end in spotify.com.
static BOOL spotifyHost(NSString *host) {
    return [host isEqualToString:@"spotify.com"] || [host hasSuffix:@".spotify.com"];
}

// Whole ad domains: every path on them is an ad, whatever it says.
static NSString *const adHosts[] = {
    @"doubleclick.net", @"googlesyndication.com", @"googleadservices.com",
    @"ad.spotify.com", @"ads.spotify.com", @"aet.spotify.com",
};

static BOOL adHost(NSString *host) {
    for (size_t i = 0; i < sizeof(adHosts) / sizeof(adHosts[0]); i++) {
        NSString *domain = adHosts[i];
        if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) return YES;
    }
    return NO;
}

// 9.2.0 dropped the bootstrap and customize endpoints: the configuration a client gets, and the
// account attributes that decide on-demand play, arrive from the resolver instead.
static BOOL isResolver(NSString *path) {
    return has(path, @"/remote-config-resolver/") && has(path, @"configuration");
}
// 账号属性：9.2.0 走 /nebula/v1/configuration/attributes，响应体就是 AccountAttributesResponse，
// 客户端按字节流读它，不经过 -body，所以在这一层改（Premium.m 的 SGPatchAttributePayload）。
static BOOL isNebulaAttributes(NSString *path) { return has(path, @"/nebula/v1/configuration/attributes"); }
static BOOL isBootstrap(NSString *path) { return has(path, @"v1/bootstrap"); }
static BOOL isCustomize(NSString *path) { return has(path, @"v1/customize"); }
static BOOL isCustomizeURL(NSURL *url) { return spotifyHost(url.host.lowercaseString ?: @"") && isCustomize(url.path.lowercaseString ?: @""); }

// The feeds Home, Search and the page under the player are built from. casita/v1/feeds is the flat
// list of tab chips, not sections. scrollsita is the lyrics layer's: left alone here on purpose.
static BOOL isFeedURL(NSURL *url) {
    if (!spotifyHost(url.host.lowercaseString ?: @"")) return NO;
    NSString *path = url.path.lowercaseString ?: @"";
    if (has(path, @"/casita/v1/feeds")) return NO;
    // LyricsHook.x owns the scroll card lists that carry tracks and rewrites them itself; every other
    // scrollsita response is a plain page feed and is filtered here.
    if (has(path, @"/scrollsita/")) {
        return !has(url.absoluteString.lowercaseString ?: @"", @"spotify:track:");
    }
    return has(path, @"/browsita/") || has(path, @"/casita/");
}

// The server's own checks of the account state. Deliberately not the logout, sign-out, session-purge,
// token-revoke, auth-expire or deletetoken endpoints: those are what the user's own sign-out uses.
static BOOL isEntitlementCheck(NSString *path) {
    return has(path, @"product-state") || (has(path, @"melody") && has(path, @"check"))
        || (has(path, @"license") && has(path, @"check"));
}

static NSString *const adPaths[] = {
    @"/ads/", @"/ad-logic/", @"/dac/view/v1/", @"/ad-slot/", @"/ad-inventory/", @"/ad-on-app-open", @"/sponsored/",
    @"/promoted/", @"/upsell/", @"/premium-upsell", @"/upsell-banner", @"/upsell-card", @"/referrals/upsell",
    @"/campaign/", @"/billboard/", @"/banner/", @"/interstitial/", @"/overlay/", @"/popup/", @"/pop-up/",
    @"/search-ad/", @"/home-ad/", @"/marquee/", @"/leavebehind", @"/leave-behind", @"/display-ad/", @"/fullbleed/",
    @"/leaderboard/", @"/ad-card/", @"/sponsored-content/", @"/sponsored-ad/", @"/native-ad/", @"/sponsored-shelf/",
    @"/sponsored-row/", @"/ad-shelf/", @"/ad-row/", @"/sponsored-item/", @"/ad-item/", @"/merchandising/",
    @"/upgrade-component/", @"/marketing/", @"/home-ads/", @"/search-ads/",
};

// Path rules run on Spotify's hosts only (callers check), so /marketing/ here is Spotify's marketing
// endpoint and not any other company's page.
static BOOL adPath(NSString *path) {
    for (size_t i = 0; i < sizeof(adPaths) / sizeof(adPaths[0]); i++) {
        if (has(path, adPaths[i])) return YES;
    }
    return has(path, @"/esperanto/") && (has(path, @"ad") || has(path, @"slot"));
}

// The first thirty seconds are a fresh login's: signup/public and customize are part of it, and
// answering them broke first launch. Only Spotify hosts, only these paths.
static BOOL isRefetch(NSString *path) {
    return has(path, @"signup/public") || has(path, @"select-ondemand-set") || has(path, @"trials-facade/start-trial")
        || has(path, @"premium-marketing/upselloffer") || (has(path, @"pendragon") && has(path, @"fetchmessagelist"))
        || has(path, @"pushka-tokens") || has(path, @"apresolve") || has(path, @"pses/screenconfig") || isCustomize(path);
}

static SGNet classify(NSURL *url) {
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path.lowercaseString ?: @"";
    BOOL mine = spotifyHost(host);
    if (premium && mine && isEntitlementCheck(path)) return SGNetBlock;
    if (ads && (adHost(host) || (mine && adPath(path)))) return SGNetBlock;
    if (premium && mine && isNebulaAttributes(path)) return SGNetPatch;
    if (premium && mine && elapsed() > 30 && isRefetch(path)) return SGNetBlock;
    if (premium && mine && (isBootstrap(path) || isCustomize(path) || isResolver(path))) return SGNetPatch;
    if (ads && isFeedURL(url)) return SGNetPatch;
    return SGNetPass;
}

// 诊断：按时间顺序记下每个 Spotify 请求的路径（不含 host、参数、令牌），上限 2000 条。
// 音频广告是服务端插进来的，只有看清插播前后客户端在请求什么，才知道该拦哪一段。
static void noteRequest(NSString *path) {
    static NSUInteger count;
    if (!ads || count >= 2000 || !path.length) return;
    count++;
    SGProbeC("REQ %s", path.UTF8String);
}

#pragma mark - bodies

static NSData *cached(void) {
    @synchronized (cacheLock) { return cachedCustomize; }
}

static void keepCustomize(NSData *body) {
    @synchronized (cacheLock) { cachedCustomize = body; }
}

static NSData *json(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

// The body a blocked request is answered with: what its reader parses for, so that nothing is
// retried and no logout path taken.
static NSData *blockedReply(NSString *path) {
    if (has(path, @"signup/public")) return json(@"{\"status\":1,\"country\":\"US\",\"is_country_launched\":true}");
    if (has(path, @"trials-facade")) return json(@"{\"result\":\"NOT_ELIGIBLE\"}");
    if (has(path, @"premium-marketing") || has(path, @"pses/screenconfig")) return json(@"{}");
    if (isEntitlementCheck(path) || has(path, @"apresolve")) return json(@"{\"status\":\"OK\"}");
    if (isCustomize(path) && cached()) return cached();
    return [NSData data];
}

// The rewritten body, or the original one and SGBodyPatchFailed/Unchanged. `outcome` is what the
// counters and the log go by: a body that parsed and had nothing to change is not a failure.
// One copy of the resolver body on disk, so the real message shape can be read offline instead of
// guessed. Written once per launch, contains no credentials.
static void dumpResolverOnce(NSData *body, NSString *path) {
    if (body.length == 0) return;
    BOOL unauth = [path rangeOfString:@"/unauth/"].location != NSNotFound;
    static BOOL doneAuth = NO, doneUnauth = NO;
    BOOL *flag = unauth ? &doneUnauth : &doneAuth;
    if (*flag) return;
    *flag = YES;
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *name = unauth ? @"resolver-unauth-dump.bin" : @"resolver-auth-dump.bin";
    if (dir) [body writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
}

static NSData *resolverPatched(NSData *body, SGBodyPatch *outcome) {
    SGPWResult measure = SGPWRewrite(body.bytes, body.length, SGPW_TARGET_RESOLVER, NULL, 0);
    if (measure.status != SGPW_OK || measure.size == 0) { *outcome = SGBodyPatchFailed; return nil; }
    NSMutableData *out = [NSMutableData dataWithLength:measure.size];
    SGPWResult wrote = SGPWRewrite(body.bytes, body.length, SGPW_TARGET_RESOLVER, out.mutableBytes, measure.size);
    if (wrote.status != SGPW_OK) { *outcome = SGBodyPatchFailed; return nil; }
    out.length = wrote.size;
    return out;
}

static NSData *patched(NSURL *url, NSData *body, SGBodyPatch *outcome) {
    SGBodyPatch result = SGBodyPatchFailed;
    NSString *lowered = url.path.lowercaseString ?: @"";
    if (isNebulaAttributes(lowered)) {
        NSData *rewritten = SGPatchAttributePayload(body);
        if (rewritten) {
            result = [rewritten isEqualToData:body] ? SGBodyPatchUnchanged : SGBodyPatchChanged;
        }
        NSData *needle = [@"premium" dataUsingEncoding:NSUTF8StringEncoding];
        BOOL premiumText = rewritten && [rewritten rangeOfData:needle options:0
                                                         range:NSMakeRange(0, rewritten.length)].location != NSNotFound;
        SGProbeC("attributes %lu -> %lu bytes %s premium=%d", (unsigned long)body.length,
                 (unsigned long)(rewritten ?: body).length,
                 result == SGBodyPatchChanged ? "rewritten" : (result == SGBodyPatchUnchanged ? "unchanged" : "unparsed"),
                 premiumText);
        if (outcome) *outcome = result;
        SGAdBlockCountOne(result == SGBodyPatchChanged ? SGAdCountRewritten
                          : (result == SGBodyPatchUnchanged ? SGAdCountUnchanged : SGAdCountFailed));
        return rewritten;
    }
    if (isResolver(url.path.lowercaseString ?: @"")) {
        dumpResolverOnce(body, url.path.lowercaseString ?: @"");
        NSData *rewritten = resolverPatched(body, &result);
        if (rewritten) result = [rewritten isEqualToData:body] ? SGBodyPatchUnchanged : SGBodyPatchChanged;
        if (outcome) *outcome = result;
        if (result == SGBodyPatchChanged) SGAdBlockCountOne(SGAdCountRewritten);
        else if (result == SGBodyPatchUnchanged) SGAdBlockCountOne(SGAdCountUnchanged);
        else SGAdBlockCountOne(SGAdCountFailed);
        SGLog(@"resolver response %lu -> %lu bytes", (unsigned long)body.length, (unsigned long)(rewritten.length));
        return rewritten;
    }
    NSData *rewritten = isFeedURL(url) ? SGStripFeed(body, &result)
                                       : (isBootstrap(url.path.lowercaseString ?: @"") ? SGPatchBootstrap(body) : SGPatchCustomize(body));
    if (rewritten) {
        result = [rewritten isEqualToData:body] ? SGBodyPatchUnchanged : SGBodyPatchChanged;
    }
    if (rewritten && isCustomizeURL(url)) keepCustomize(rewritten);
    if (outcome) *outcome = result;
    switch (result) {
        case SGBodyPatchChanged:
            SGAdBlockCountOne(SGAdCountRewritten);
            SGLog(@"rewrote a response %lu -> %lu bytes", (unsigned long)body.length, (unsigned long)rewritten.length);
            return rewritten;
        case SGBodyPatchUnchanged:
            SGAdBlockCountOne(SGAdCountUnchanged);
            return rewritten;
        default:
            SGAdBlockCountOne(SGAdCountFailed);
            SGLog(@"could not rewrite a response of %lu bytes, passed through", (unsigned long)body.length);
            SGProbeC("patch failed %lu bytes", (unsigned long)body.length);
            return nil;
    }
}

#pragma mark - the delegate's three calls

// Data handed to the delegate by the mod goes through its hooked didReceiveData like Spotify's own,
// with the pass mark on the task so the hook lets it by.
static void deliver(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    // 空 body 也要交：被拦的请求正是靠"一个 0 字节的 body"告诉读者没有内容，跳过会让人一直等。
    objc_setAssociatedObject(task, &kPassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [delegate URLSession:session dataTask:(NSURLSessionDataTask *)task didReceiveData:data];
    objc_setAssociatedObject(task, &kPassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A customize the server says has not changed, answered with the rewritten one from last time.
static NSHTTPURLResponse *replayFor(NSURLSessionTask *task, NSURLResponse *response) {
    if (!premium || ![response isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)response).statusCode != 304) return nil;
    NSURL *url = task.currentRequest.URL;
    if (!isCustomizeURL(url) || !cached()) return nil;
    objc_setAssociatedObject(task, &kServedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/2.0" headerFields:@{}];
}

// 这一次任务算什么，在 didReceiveResponse 时定下来：elapsed() 跨过 30 秒边界时，同一个任务在
// 收数据与收尾时的分类必须一致，否则 customize 会被当成"过期的重取"答成空 JSON。
static SGNet kindOf(NSURLSessionTask *task) {
    NSNumber *kind = objc_getAssociatedObject(task, &kKindKey);
    return kind ? (SGNet)kind.integerValue : classify(task.currentRequest.URL);
}

static NSMutableData *bufferFor(NSURLSessionTask *task) {
    NSMutableData *buffer = objc_getAssociatedObject(task, &kBufferKey);
    if (!buffer) objc_setAssociatedObject(task, &kBufferKey, (buffer = [NSMutableData data]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return buffer;
}

// The end of a task: the answer for a blocked one, the rewritten body for a held one, the pass for
// everything else.
static void complete(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSError *error, void (^finish)(NSError *)) {
    NSURL *url = task.currentRequest.URL;
    NSMutableData *buffer = objc_getAssociatedObject(task, &kBufferKey);
    BOOL overflowed = objc_getAssociatedObject(task, &kOverflowKey) != nil;
    objc_setAssociatedObject(task, &kBufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(task, &kOverflowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(task, &kServedKey)) {
        finish(nil);
        return;
    }
    switch (kindOf(task)) {
        case SGNetBlock:
            SGAdBlockCountOne(SGAdCountRequests);
            SGLog(@"answered a blocked request empty");
            deliver(delegate, session, task, blockedReply(url.path.lowercaseString ?: @""));
            finish(nil);
            return;
        case SGNetPatch:
            if (error) {
                finish(error);
                return;
            }
            // 超限时身体已经在 didReceiveData 里原样交下去了，这里只收尾。
            if (overflowed) {
                finish(nil);
                return;
            }
            // Nothing to rewrite: a 304, or a body of no bytes. The delegate is told of a body either
            // way, since a completion with none hangs some readers.
            if (!buffer) {
                SGProbeC("patch with no body: %s", (url.path.lowercaseString ?: @"?").UTF8String);
                NSData *replay = isCustomizeURL(url) ? cached() : nil;
                deliver(delegate, session, task, replay ?: [NSData data]);
                finish(nil);
                return;
            }
            deliver(delegate, session, task, patched(url, buffer, NULL) ?: buffer);
            finish(nil);
            return;
        default:
            finish(error);
    }
}

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    objc_setAssociatedObject(task, &kKindKey, @(classify(task.currentRequest.URL)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    noteRequest(task.currentRequest.URL.path.lowercaseString);
    NSHTTPURLResponse *replay = replayFor(task, response);
    %orig(session, task, replay ?: response, handler);
    if (replay) deliver((id)self, session, task, cached());
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (objc_getAssociatedObject(task, &kPassKey)) {
        %orig;
        return;
    }
    switch (kindOf(task)) {
        case SGNetBlock:
            return;   // 广告/纠错请求的字节不交付；完成时给空答
        case SGNetPatch:
            // 已经超限：本块与后续块原样透传，不再攒。
            if (objc_getAssociatedObject(task, &kOverflowKey)) {
                %orig;
                return;
            }
            if (bufferFor(task).length + data.length <= kBufferLimit) {
                [bufferFor(task) appendData:data];
                return;
            }
            // 超限：已攒的原始 body 一次性回投，本块跟上，之后全部透传。不丢任何一个分块。
            SGAdBlockCountOne(SGAdCountOversize);
            SGLog(@"a response passed the %lu byte buffer limit, passed through unrewritten", (unsigned long)kBufferLimit);
            {
                NSData *accumulated = [objc_getAssociatedObject(task, &kBufferKey) copy];
                objc_setAssociatedObject(task, &kBufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(task, &kOverflowKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (accumulated.length) %orig(session, task, accumulated);
                %orig(session, task, data);
            }
            return;
        default:
            %orig;
            return;
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    complete((id)self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    objc_setAssociatedObject(task, &kKindKey, @(classify(task.currentRequest.URL)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    noteRequest(task.currentRequest.URL.path.lowercaseString);
    NSHTTPURLResponse *replay = replayFor(task, response);
    %orig(session, task, replay ?: response, handler);
    if (replay) deliver((id)self, session, task, cached());
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (objc_getAssociatedObject(task, &kPassKey)) {
        %orig;
        return;
    }
    switch (kindOf(task)) {
        case SGNetBlock:
            return;
        case SGNetPatch:
            if (objc_getAssociatedObject(task, &kOverflowKey)) {
                %orig;
                return;
            }
            if (bufferFor(task).length + data.length <= kBufferLimit) {
                [bufferFor(task) appendData:data];
                return;
            }
            SGAdBlockCountOne(SGAdCountOversize);
            SGLog(@"a response passed the %lu byte buffer limit, passed through unrewritten", (unsigned long)kBufferLimit);
            {
                NSData *accumulated = [objc_getAssociatedObject(task, &kBufferKey) copy];
                objc_setAssociatedObject(task, &kBufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(task, &kOverflowKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (accumulated.length) %orig(session, task, accumulated);
                %orig(session, task, data);
            }
            return;
        default:
            %orig;
            return;
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    complete((id)self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end

#pragma mark - before a request leaves

// The re-fetches that could put the real product state back, or drop the push token, use sessions
// of their own that the delegate hooks do not see; they are cancelled at the task. login5 and the
// Google token stay: blocking those was a crash loop. deletetoken is not here either: it is part of
// signing out, and signing out has to keep working.
%group Premium
%hook NSURLSessionTask
- (void)resume {
    NSURL *url = self.currentRequest.URL ?: self.originalRequest.URL;
    NSString *host = url.host.lowercaseString ?: @"", *path = url.path.lowercaseString ?: @"";
    if (spotifyHost(host) && elapsed() > 30 && (has(path, @"signup/public") || has(path, @"pses/screenconfig")
                                               || isCustomize(path) || has(host, @"apresolve"))) {
        SGAdBlockCountOne(SGAdCountRequests);
        SGLog(@"cancelled a re-fetch before it left");
        [self cancel];
        return;
    }
    %orig;
}
%end
%end

// The config comes back 304 with no body when the app holds a copy of it and asks whether that is still
// current, and a copy taken while Spoof Premium was off is the server's own: the mod then has nothing to
// rewrite, and the account stays free until the server changes the config (device 2026-09-21). So the two
// go out without the question, and the server always answers in full.
static NSURLRequest *unconditional(NSURLRequest *request) {
    NSString *host = request.URL.host.lowercaseString ?: @"", *path = request.URL.path.lowercaseString ?: @"";
    if (!spotifyHost(host) || !(isBootstrap(path) || isCustomize(path) || isNebulaAttributes(path))) return nil;
    if (![request valueForHTTPHeaderField:@"If-None-Match"] && ![request valueForHTTPHeaderField:@"If-Modified-Since"]) return nil;
    NSMutableURLRequest *plain = [request mutableCopy];
    [plain setValue:nil forHTTPHeaderField:@"If-None-Match"];
    [plain setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
    plain.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    SGProbeC("stripped validators on %s", path.UTF8String);
    return plain;
}

%group PremiumRequests
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(unconditional(request) ?: request);
}
%end
%end

// The sessions Spotify makes are __NSURLSessionLocal; hooked as well only when that class answers
// dataTaskWithRequest: itself, since a hook on an inherited method would sit on NSURLSession's twice.
%group PremiumLocalRequests
%hook __NSURLSessionLocal
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(unconditional(request) ?: request);
}
%end
%end

%ctor {
    ads = SGHidden(SGKeyHideAds);
    premium = SGHidden(SGKeyFakePremium);
    if (!ads && !premium) return;
    started = NSDate.date;
    cacheLock = [NSObject new];
    %init;
    if (premium) {
        %init(Premium);
        %init(PremiumRequests);
        SEL selector = @selector(dataTaskWithRequest:);
        Class local = objc_getClass("__NSURLSessionLocal");
        Method own = local ? class_getInstanceMethod(local, selector) : NULL;
        if (own && own != class_getInstanceMethod(NSURLSession.class, selector)) %init(PremiumLocalRequests);
    }
    SGRequireClasses(@[@"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession"]);
}
