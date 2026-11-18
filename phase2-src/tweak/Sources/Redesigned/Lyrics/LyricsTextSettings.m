// Drag the three texts of a line into size order, largest first.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "LyricsText.h"

@interface SGRLyricsTextPage : SGPage
@end

@implementation SGRLyricsTextPage {
    NSMutableArray<NSNumber *> *_order;
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"文字大小";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _order = [SGRLyricsTextOrder() mutableCopy];
    self.tableView.editing = YES;
    _footer = SGNote(@"发音与翻译从歌词角落的按钮开启。");
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;   // 灵动岛歌词字体 / 从大到小排序
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return (NSInteger)_order.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, section == 0 ? @"灵动岛歌词" : @"从大到小");
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        UITableViewCell *cell = SGDequeueCell(table, @"island-font");
        SGFillCell(cell, @"灵动岛歌词字体", nil, nil, @"textformat.size");
        UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"小", @"标准", @"大"]];
        control.selectedSegmentIndex = SGIslandLyricsFontSize();
        control.selectedSegmentTintColor = SGGreen();
        [control setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: SGSubtitleFont()} forState:UIControlStateNormal];
        control.tag = 100;
        [control addTarget:self action:@selector(fontSizeChanged:) forControlEvents:UIControlEventValueChanged];
        [control sizeToFit];
        cell.accessoryView = control;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"text");
    SGRLyricsText text = _order[(NSUInteger)path.row].integerValue;
    NSArray<NSString *> *sizes = @[@"最大", @"较小", @"最小"];
    NSString *symbol = text == SGRLyricsTextLyrics ? @"music.mic" : text == SGRLyricsTextPronunciation ? @"character.phonetic" : @"character.bubble";
    SGFillCell(cell, SGRLyricsTextName(text), sizes[MIN((NSUInteger)path.row, sizes.count - 1)], nil, symbol);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)fontSizeChanged:(UISegmentedControl *)control {
    SGSetInt(SGKeyIslandLyricsFontSize, control.selectedSegmentIndex);
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    if (from.section != 1 || to.section != 1) return;
    NSNumber *text = _order[(NSUInteger)from.row];
    [_order removeObjectAtIndex:(NSUInteger)from.row];
    [_order insertObject:text atIndex:(NSUInteger)to.row];
    SGRSetLyricsTextOrder(_order);
    [table reloadData];   // the sizes under the names have all moved
}

@end

SGModRow *SGRLyricsTextSizesRow(void) {
    return SGPageRow(@"文字大小", ^UIViewController *{ return [SGRLyricsTextPage new]; });
}
