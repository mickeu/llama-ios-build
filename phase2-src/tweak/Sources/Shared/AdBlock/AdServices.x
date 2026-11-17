// The services behind every ad surface and Premium prompt, each an SPTService Spotify starts by
// sending it -load. Hooked to do nothing, the surface is never built: the brand ad on Home, the card
// under the player, the card among the player's scroll cards, the in-stream ad, and the sheets and
// cards that sell Premium.
//
// 适配（9.2.0 实测转储 spotify-ad-re/rev/main.methods.txt）：
//  * 上游 18 个 -load 目标里 8 个在 9.2.0 没有 -load（类在，只有 init/_injectDependenciesWithProvider:），
//    装上去只会是空 hook。这里只留"类与方法都在、type encoding 对得上"的 10 个，其余不写死代码，
//    也不拿 init 去猜生命周期入口。
//  * 上游两个 view 的 -didMoveToSuperview 打的是 UIView 的继承实现（两个类都没有自己的这个方法），
//    Logos 对"非本类实现"的处理没在真机验证过，最坏会影响所有视图。整段去掉，不碰继承方法。
//  * 计数只按"广告服务 / 推销服务"两类，不写类名以外的任何内容。
#import "Core/SGCore.h"
#import "AdBlock.h"
#import "SGProbeLog.h"

%group Ads

%hook _TtC19AdsPlatform_AdsImpl14AdsServiceImpl
- (void)load { SGAdBlockCountOne(SGAdCountServices); }
%end
%hook _TtC29AdsNowPlaying_InStreamAdsImpl18InStreamAdsService
- (void)load { SGAdBlockCountOne(SGAdCountServices); }
%end
%hook _TtC29AdsNowPlaying_EmbeddedNPVImpl22EmbeddedNPVServiceImpl
- (void)load { SGAdBlockCountOne(SGAdCountServices); }
%end
%hook _TtC35AdsEmbedded_AdsSponsoredContextImpl30AdsSponsoredContextServiceImpl
- (void)load { SGAdBlockCountOne(SGAdCountServices); }
%end
%hook _TtC48AdsEmbedded_AdsSponsoredContextNPBAttachmentImpl43AdsSponsoredContextNPBAttachmentServiceImpl
- (void)load { SGAdBlockCountOne(SGAdCountServices); }
%end
// The leavebehind card among the player's scroll cards. It has no -load; its card is added the way
// lyrics and credits add theirs, so it is kept off the list instead (9.2.0: v24@0:8@16).
%hook _TtC32AdsEmbedded_EmbeddedCTACardsImpl23EmbeddedCTACardsService
- (void)registerScrollProviderIn:(id)registry { SGAdBlockCountOne(SGAdCountServices); }
%end

%end

%group Upsells

%hook _TtC45ReinventFree_ContextualUpsellPremiumPromoImpl39ContextualUpsellPremiumPromoServiceImpl
- (void)load { SGAdBlockCountOne(SGAdCountUpsells); }
%end
%hook _TtC28Jam_FreeHostedJamsUpsellImpl31FreeHostedJamsUpsellServiceImpl
- (void)load { SGAdBlockCountOne(SGAdCountUpsells); }
%end
%hook _TtC30Jam_FreeUserSkipUpsellPageImpl29FreeUserSkipUpsellPageService
- (void)load { SGAdBlockCountOne(SGAdCountUpsells); }
%end
%hook _TtC38Jam_FreeUserShuffleUpsellSheetPageImpl37FreeUserShuffleUpsellSheetPageService
- (void)load { SGAdBlockCountOne(SGAdCountUpsells); }
%end

%end

%ctor {
    SGProbeC("adblock ctor: ads=%d upsells=%d premium=%d", SGHidden(SGKeyHideAds), SGHidden(SGKeyHideUpsells), SGHidden(SGKeyFakePremium));
    if (SGHidden(SGKeyHideAds)) {
        %init(Ads);
        SGProbeC("ad services killed: platform/in-stream/embeddednpv/sponsoredcontext/npb/ctacards");
        SGRequireClasses(@[
            @"_TtC19AdsPlatform_AdsImpl14AdsServiceImpl",
            @"_TtC29AdsNowPlaying_InStreamAdsImpl18InStreamAdsService",
            @"_TtC29AdsNowPlaying_EmbeddedNPVImpl22EmbeddedNPVServiceImpl",
            @"_TtC35AdsEmbedded_AdsSponsoredContextImpl30AdsSponsoredContextServiceImpl",
            @"_TtC48AdsEmbedded_AdsSponsoredContextNPBAttachmentImpl43AdsSponsoredContextNPBAttachmentServiceImpl",
            @"_TtC32AdsEmbedded_EmbeddedCTACardsImpl23EmbeddedCTACardsService",
        ]);
    }
    if (SGHidden(SGKeyHideUpsells)) {
        %init(Upsells);
        SGProbeC("upsell services killed: contextualpromo/freejams/skipupsell/shuffleupsell");
        SGRequireClasses(@[
            @"_TtC45ReinventFree_ContextualUpsellPremiumPromoImpl39ContextualUpsellPremiumPromoServiceImpl",
            @"_TtC28Jam_FreeHostedJamsUpsellImpl31FreeHostedJamsUpsellServiceImpl",
            @"_TtC30Jam_FreeUserSkipUpsellPageImpl29FreeUserSkipUpsellPageService",
            @"_TtC38Jam_FreeUserShuffleUpsellSheetPageImpl37FreeUserShuffleUpsellSheetPageService",
        ]);
    }
}
