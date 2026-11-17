// The Vibrations sections of the Player page, under either look (App/Pages.m puts them there): a card
// per switch, the way the Audio effects page has one per effect, each opening out into its settings while
// its switch is on. Controls has its strength; Music Haptics its strength and what it follows, a choice
// that also says whether the rumble plays, rather than a switch of its own that one choice would leave
// with nothing to do.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Haptics.h"

static NSString *const kMusicHapticsInfo = @"iPhone 会跟随 Spotify 正在播放的声音，随鼓点轻敲、随低音震动，效果类似 Apple Music 的“音乐触感”。\n\n它跟随此 iPhone 通过扬声器或耳机播放的声音，且仅在 Spotify 打开时生效：iOS 不会为后台应用播放触感，通过 Connect 在另一台设备播放的歌曲在此处也没有可跟随的声音。";

static NSArray<NSString *> *followsNames(void) {
    return @[@"全部", @"节拍", @"低音"];
}

static NSArray<NSString *> *followsNotes(void) {
    return @[@"每个底鼓和军鼓各一次轻敲，低音下方有震动",
             @"每个底鼓和军鼓各一次轻敲，无震动",
             @"每个底鼓一次轻敲，低音下方有震动"];
}

static void strengthRange(NSString *key, NSInteger *minimum, NSInteger *maximum) {
    BOOL music = [key isEqualToString:SGKeyMusicStrength];
    *minimum = music ? SGMusicStrengthMin : SGControlStrengthMin;
    *maximum = music ? SGMusicStrengthMax : SGControlStrengthMax;
}

double SGHapticsStrength(NSString *key) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return MAX(minimum, MIN(maximum, SGInt(key, 100))) / 100.0;
}

SGMusicFollows SGMusicHapticsFollows(void) {
    NSInteger follows = SGInt(SGKeyMusicFollows, SGMusicFollowsEverything);
    return follows >= SGMusicFollowsEverything && follows <= SGMusicFollowsBass ? (SGMusicFollows)follows : SGMusicFollowsEverything;
}

// A percentage slider over a strength key, telling `changed` each step it stores.
static SGModRow *strengthRow(NSString *key, void (^changed)(void)) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return SGSliderRow(@"强度", nil, minimum, maximum, SGStrengthStep,
        ^double { return SGHapticsStrength(key) * 100; },
        ^(double value) {
            SGSetInt(key, lround(value));
            if (changed) changed();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; });
}

NSArray<SGModSection *> *SGVibrationsSections(void) {
    SGModRow *controls = SGSwitchRow(@"控制项", nil, SGKeyControlHaptics);
    SGModRow *controlStrength = strengthRow(SGKeyControlStrength, ^{
        // Felt as it is set: a tap at the new strength with each step.
        SGPlayFeedback(SGFeedbackAdd);
    });
    controlStrength.visible = ^BOOL { return SGEnabled(SGKeyControlHaptics); };

    SGModRow *music = SGOptionRow(@"音乐触感", nil, SGKeyMusicHaptics);
    music.info = kMusicHapticsInfo;
    music.changed = ^(BOOL on) { SGSetMusicHapticsEnabled(on); };
    BOOL (^musicOn)(void) = ^BOOL { return SGFlag(SGKeyMusicHaptics, NO); };
    SGModRow *musicStrength = strengthRow(SGKeyMusicStrength, ^{ SGMusicHapticsSettingsChanged(); });
    musicStrength.visible = musicOn;
    SGModRow *follows = SGChoiceRow(@"跟随", nil, SGKeyMusicFollows, followsNames(), SGMusicFollowsEverything);
    follows.choiceNotes = followsNotes();
    follows.chosen = ^(__unused NSInteger index) { SGMusicHapticsSettingsChanged(); };
    follows.visible = musicOn;

    return @[
        SGSection(@"振动", @[SGWithSymbol(controls, @"hand.tap"), controlStrength]),
        SGSection(nil, @[SGWithSymbol(music, @"waveform"), musicStrength, follows]),
    ];
}
