// Labs: Spotify's flags for features it built and did not ship; every row forces one flag.
#import "Settings/SGModPage.h"
#import "Flags.h"

static UIViewController *martiniPage(void) {
    return [[SGModPage alloc] initWithTitle:@"AI 聊天 (Martini)" intro:SGRestartNote sections:@[
        SGSection(@"在主页", @[
            SGFlagRow(@"聊天入口", @"ios-home-evopage-impl.interactive_entrypoint_enabled"),
            SGFlagRow(@"背后的 Martini", @"ios-home-evopage-impl.interactive_entrypoint_martini_enabled"),
            SGFlagRow(@"悬浮聊天", @"ios-home-evopage-impl.interactive_entrypoint_floating_chat_enabled"),
            SGFlagRow(@"麦克风", @"ios-home-evopage-impl.interactive_entrypoint_mic_enabled"),
            SGFlagRow(@"发光胶囊", @"ios-home-evopage-impl.interactive_entrypoint_pill_glow_enabled"),
        ]),
        SGSection(@"聊天", @[
            SGFlagRow(@"意图胶囊", @"ios-martini-floatingchat-impl.intent_pills_enabled"),
            SGFlagRow(@"思考状态", @"ios-martini-floatingchat-impl.thinking_states_enabled"),
            SGFlagRow(@"语音录制", @"ios-martini-floatingchat-impl.voice_recording_enabled"),
        ]),
        SGSection(@"在播放器", @[
            SGFlagRow(@"聊天入口", @"ios-martini-npvcardprovider-impl.floating_chat_entry_point_enabled"),
        ]),
    ] footer:nil];
}

UIViewController *SGLabsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"实验室" intro:@"未发布功能；部分在你的版本上不起作用。重启 Spotify 后生效。" sections:@[
        SGSection(nil, @[
            SGWithSymbol(SGPageRow(@"AI 聊天 (Martini)", ^UIViewController *{ return martiniPage(); }), @"bubble.left.and.bubble.right"),
        ]),
        SGSection(@"音乐库", @[
            SGFlagRow(@"从文件应用导入本地文件", @"ios-feature-localfiles.documents_enabled"),
        ]),
        SGSection(@"主屏幕小组件", @[
            SGFlagRow(@"进度条", @"ios-widgets-widgetremoteconfig-impl.progress_bar_enabled"),
        ]),
        SGNotedSection(@"睡眠定时", @[
            SGFlagRow(@"淡出", @"ios-feature-sleeptimer.enable_fade_out"),
            SGFlagRow(@"一分钟选项", @"ios-feature-sleeptimer.enable_one_minute_option"),
            SGFlagRow(@"选项面板", @"ios-feature-sleeptimer.use_options_sheet"),
        ], @"选项面板在新版界面始终开启。"),
        SGSection(@"播放器", @[
            SGFlagRow(@"封面上的贪吃蛇", @"ios-feature-cover-art-snake.enabled"),
        ]),
        SGSection(@"播客评论", @[
            SGFlagRow(@"评论卡片", @"ios-feature-comments.enable_comments_card"),
            SGFlagRow(@"置顶评论", @"ios-feature-comments.enable_pinned_comments"),
            SGFlagRow(@"多种反应", @"ios-feature-comments.enable_multi_reactions"),
        ]),
    ] footer:nil];
}
