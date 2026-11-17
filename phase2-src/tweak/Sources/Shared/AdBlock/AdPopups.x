// The Premium prompts Spotify presents as Encore pop-ups, dropped when their words sell Premium
// (EeveeSpotify's UpsellPopupBlocker). The words are read where the dialog model is made, since
// the dialog handed to the presenter does not expose them on every build; the presenter reads
// them itself as a fallback.
#import "Core/SGCore.h"
#import "AdBlock.h"

static NSString *const words[] = {
    @"premium", @"upgrade", @"subscribe", @"subscription", @"listening without limits", @"unlimited skips",
    @"play the songs you love", @"go premium", @"like listening", @"free account", @"ad-free", @"ad free", @"try free",
    @"get premium", @"start premium", @"upsell", @"paywall", @"free tier", @"limited listening",
    @"předplatn", @"bez reklam",
};

static char kUpsellKey;

static BOOL sells(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    text = text.lowercaseString;
    for (size_t i = 0; i < sizeof(words) / sizeof(words[0]); i++) {
        if ([text containsString:words[i]]) return YES;
    }
    return NO;
}

static void mark(id object) {
    objc_setAssociatedObject(object, &kUpsellKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL marked(id object) {
    return objc_getAssociatedObject(object, &kUpsellKey) != nil;
}

// valueForKey: on a key the object lacks raises, so it is only asked what it answers to.
static id readKey(id object, NSString *key) {
    return [object respondsToSelector:NSSelectorFromString(key)] ? [object valueForKey:key] : nil;
}

%hook SPTEncorePopUpDialogModel
- (id)initWithTitle:(NSString *)title description:(NSString *)description image:(id)image primaryButtonTitle:(NSString *)primary secondaryButtonTitle:(NSString *)secondary {
    id model = %orig;
    if (model && (sells(title) || sells(description) || sells(primary) || sells(secondary))) mark(model);
    return model;
}
%end

%hook SPTEncorePopUpDialog
- (void)update:(id)model {
    if (marked(model)) mark(self);
    %orig;
}
%end

// 9.2.0 的转储里这个方法是 `B24@0:8@16`（BOOL），上游写成了 void：方法不丢弃时调用方读的是
// 未定义的返回值。丢弃时明确答 NO（没有展示），放行时把 %orig 的回答原样交回去。日志只说丢了一个
// 弹窗，不写标题与正文（那是服务器文案，可能带账号相关内容）。
%hook SPTEncorePopUpPresenter
- (BOOL)presentPopUp:(id)popUp {
    id model = readKey(popUp, @"model") ?: popUp;
    NSString *title = readKey(model, @"title") ?: readKey(model, @"dialogTitle");
    NSString *body = readKey(model, @"descriptionText") ?: readKey(model, @"body") ?: readKey(model, @"subtitle");
    if (marked(popUp) || sells(title) || sells(body)) {
        SGAdBlockCountOne(SGAdCountPopups);
        SGLog(@"dropped a pop-up");
        return NO;
    }
    return %orig;
}
%end

%ctor {
    if (!SGHidden(SGKeyHideUpsells)) return;
    %init;
    SGRequireClasses(@[@"SPTEncorePopUpDialogModel", @"SPTEncorePopUpDialog", @"SPTEncorePopUpPresenter"]);
}
