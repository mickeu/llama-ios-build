#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import <ImageIO/ImageIO.h>

// 仅读取当前 IPA 已注册的图标；所有原始 PNG 都只在后台 autoreleasepool 内短暂存在。
static NSArray<NSString *> *SGIconContainerKeys(void) {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
        ? @[@"CFBundleIcons~ipad", @"CFBundleIcons"]
        : @[@"CFBundleIcons"];
}

static NSDictionary *SGIconContainer(NSString *key) {
    NSDictionary *value = NSBundle.mainBundle.infoDictionary[key];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSString *SGIconDisplayName(NSString *key) {
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{@"Pinkly": @"粉红", @"EeveeSpotifyAnime": @"伊布动漫", @"SmallvilleSpotify": @"小镇", @"HelloKittify": @"凯蒂猫", @"Goldify": @"金色", @"SpotifyPurpleNeon": @"紫色霓虹", @"SpotifyPlatinum": @"铂金", @"EvilSpotifyDisco": @"暗黑迪斯科", @"SpotifyMiku": @"初音未来", @"SpotifyMonochrome": @"黑白", @"EvilSpotify": @"暗黑", @"SpotifyDarkBlue": @"深蓝", @"SpotifyBlueDiamond": @"蓝钻", @"SpotifyGloss": @"高光", @"SpotifyLight": @"浅色", @"SupermanSpotify": @"超人经典", @"SpotifyDisco": @"迪斯科", @"SpotifyToys": @"玩具", @"Greenify": @"绿色", @"SupermanSpotify2": @"超人 II", @"SpotifyTennis": @"网球", @"SpotifyScrible": @"涂鸦", @"Asta_Liebe(Red)": @"阿斯塔红", @"Asta_Liebe(Green)": @"阿斯塔绿", @"Eevify": @"伊布", @"MikuSpotify": @"初音", @"Spotify2012": @"经典 2012", @"SpotifyPink": @"粉色 Spotify", @"EeveeCustom": @"伊布自定义", @"SpotifyFrieren": @"芙莉莲", @"Supermanify": @"超人", @"SpotifyJuicy": @"果汁", @"SpotifyDeepGreen": @"深绿色", @"zxcvbn": @"自定义图标"};
    });
    return names[key] ?: key;
}

@interface SGIconCatalog : NSObject
@property (nonatomic, readonly) NSArray<NSString *> *keys;
- (nullable NSString *)baseNameForKey:(nullable NSString *)key;
@end

@implementation SGIconCatalog {
    NSDictionary<NSString *, NSString *> *_baseNames;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSMutableDictionary<NSString *, NSString *> *baseNames = [NSMutableDictionary dictionary];
    for (NSString *containerKey in SGIconContainerKeys()) {
        NSDictionary *container = SGIconContainer(containerKey);
        NSDictionary *primary = container[@"CFBundlePrimaryIcon"];
        NSArray *primaryFiles = [primary[@"CFBundleIconFiles"] isKindOfClass:NSArray.class] ? primary[@"CFBundleIconFiles"] : nil;
        if ([primaryFiles.firstObject isKindOfClass:NSString.class] && !baseNames[@"__primary__"]) baseNames[@"__primary__"] = primaryFiles.firstObject;
        NSDictionary *alternates = container[@"CFBundleAlternateIcons"];
        if (![alternates isKindOfClass:NSDictionary.class]) continue;
        [alternates enumerateKeysAndObjectsUsingBlock:^(id key, id entry, __unused BOOL *stop) {
            if (![key isKindOfClass:NSString.class] || ![(NSString *)key length] || ![entry isKindOfClass:NSDictionary.class]) return;
            NSArray *files = [entry[@"CFBundleIconFiles"] isKindOfClass:NSArray.class] ? entry[@"CFBundleIconFiles"] : nil;
            if ([files.firstObject isKindOfClass:NSString.class] && !baseNames[key]) baseNames[key] = files.firstObject;
        }];
    }
    _baseNames = [baseNames copy];
    _keys = [[[_baseNames.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, __unused NSDictionary *bindings) { return ![key isEqualToString:@"__primary__"]; }]] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] copy];
    return self;
}

- (NSString *)baseNameForKey:(NSString *)key { return _baseNames[key ?: @"__primary__"]; }
@end

static SGIconCatalog *SGIcons(void) {
    static SGIconCatalog *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = [SGIconCatalog new]; });
    return catalog;
}

static NSString *SGIconCacheKey(NSString *key) { return key ?: @"__primary__"; }
static CGFloat SGIconPreviewSide(void) { return 44.0; }

// 首次由页面主线程调用；后台只读取已冻结的标量，不访问 UIKit screen 对象。
static CGFloat SGIconPreviewScale(void) {
    static CGFloat scale;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ scale = UIScreen.mainScreen.scale; });
    return scale;
}

static NSCache<NSString *, UIImage *> *SGIconPreviewCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 35;
        CGFloat scale = SGIconPreviewScale();
        cache.totalCostLimit = (NSUInteger)(35 * SGIconPreviewSide() * SGIconPreviewSide() * 4 * scale * scale);
    });
    return cache;
}

static dispatch_queue_t SGIconPreviewQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.spotifyglass.icon-preview", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static UIImage *SGIconCachedPreview(NSString *key) {
    return [SGIconPreviewCache() objectForKey:SGIconCacheKey(key)];
}

static UIImage *SGIconDecodePreview(NSString *key) {
    @autoreleasepool {
        if ([key isEqualToString:@"__primary__"]) key = nil;
        NSString *base = [SGIcons() baseNameForKey:key];
        if (!base.length) return nil;
        NSString *path = [NSBundle.mainBundle pathForResource:[base stringByAppendingString:@"@3x"] ofType:@"png"];
        if (!path && !key) path = [NSBundle.mainBundle pathForResource:[base stringByAppendingString:@"@2x"] ofType:@"png"];
        if (!path.length) return nil;
        NSURL *url = [NSURL fileURLWithPath:path];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (!source) return nil;
        CGFloat scale = SGIconPreviewScale();
        CGFloat pixels = SGIconPreviewSide() * scale;
        NSDictionary *options = @{
            (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(ceil(pixels)),
            (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
            (__bridge NSString *)kCGImageSourceShouldCache: @NO,
        };
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        CFRelease(source);
        if (!image) return nil;
        UIImage *thumbnail = [UIImage imageWithCGImage:image scale:scale orientation:UIImageOrientationUp];
        CGImageRelease(image);
        return thumbnail;
    }
}

static void SGIconPreloadAllPreviews(NSArray<NSString *> *keys, dispatch_block_t completion) {
    dispatch_async(SGIconPreviewQueue(), ^{
        for (NSString *key in keys) {
            NSString *cacheKey = SGIconCacheKey(key);
            if ([SGIconPreviewCache() objectForKey:cacheKey]) continue;
            UIImage *image = SGIconDecodePreview(key);
            if (!image) continue;
            CGFloat scale = image.scale;
            NSUInteger cost = (NSUInteger)(image.size.width * image.size.height * scale * scale * 4);
            [SGIconPreviewCache() setObject:image forKey:cacheKey cost:cost];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(); });
    });
}

@interface SGAppIconPage : SGPage @end
@implementation SGAppIconPage { NSArray<NSString *> *_keys; UIView *_footer; NSString *_selectedKey; }
- (instancetype)init { if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil; _keys = SGIcons().keys; _selectedKey = [NSUserDefaults.standardUserDefaults stringForKey:@"spotifyglass.selectedIcon"] ?: UIApplication.sharedApplication.alternateIconName; self.title = @"切换图标"; _footer = SGNote(@"每次切换后，系统会显示确认提示。选择“恢复默认图标”可恢复 Spotify 原图标。"); return self; }
- (void)viewDidLoad { [super viewDidLoad]; (void)SGIconPreviewScale(); self.tableView.tableFooterView = _footer; [self SGPreloadPreviews]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)viewWillLayoutSubviews { [super viewWillLayoutSubviews]; SGFitNote(self.tableView, _footer, 16, 24); }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; SGInsetForBars(self.tableView); }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return (NSInteger)_keys.count + 1; }
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section { return CGFLOAT_MIN; }
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section { return CGFLOAT_MIN; }
- (NSString *)SGKeyAtPath:(NSIndexPath *)path { return path.row == 0 ? nil : _keys[(NSUInteger)path.row - 1]; }
- (void)SGPreloadPreviews {
    NSMutableArray<NSString *> *keys = [_keys mutableCopy];
    [keys insertObject:@"__primary__" atIndex:0];
    __weak typeof(self) weakSelf = self;
    SGIconPreloadAllPreviews(keys, ^{
        [weakSelf.tableView reloadData];
    });
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"appicon"); NSString *key = [self SGKeyAtPath:path];
    SGFillCell(cell, key ? SGIconDisplayName(key) : @"恢复默认图标", nil, nil, nil);
    UIListContentConfiguration *content = [(UIListContentConfiguration *)cell.contentConfiguration copy];
    content.image = SGIconCachedPreview(key); content.imageProperties.maximumSize = CGSizeMake(44, 44); content.imageProperties.reservedLayoutSize = CGSizeMake(44, 44); content.imageToTextPadding = 14; cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryView = nil;
    if ((!key && !_selectedKey.length) || [key isEqualToString:_selectedKey]) { UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16); tick.tintColor = SGGreen(); cell.accessoryView = tick; }
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES]; NSString *key = [self SGKeyAtPath:path];
    if ((!key && !_selectedKey.length) || [key isEqualToString:_selectedKey]) return;
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication setAlternateIconName:key completionHandler:^(NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error) {
            [self.tableView reloadData];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"图标切换失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]]; [SGTopController() presentViewController:alert animated:YES completion:nil];
            return;
        }
        self->_selectedKey = key;
        if (key) [NSUserDefaults.standardUserDefaults setObject:key forKey:@"spotifyglass.selectedIcon"];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.selectedIcon"];
        [self.tableView reloadData];
    }); }];
}
@end

SGModRow *SGAppIconRow(void) {
    if (SGIcons().keys.count == 0) return nil;
    SGModRow *row = SGPageRow(@"切换图标", ^UIViewController *{ return [SGAppIconPage new]; });
    row.value = ^NSString *{ NSString *key = UIApplication.sharedApplication.alternateIconName; return key ? SGIconDisplayName(key) : @"默认图标"; };
    return row;
}
