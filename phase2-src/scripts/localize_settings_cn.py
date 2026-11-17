from pathlib import Path
R=Path(__file__).resolve().parent.parent
M={
'@"Appearance"':'@"外观"','@"Redesigned UI"':'@"新版界面"','@"Display"':'@"显示"','@"Lyrics"':'@"歌词"','@"Blocked artists"':'@"已屏蔽艺人"','@"Gestures"':'@"手势"','@"Now playing bar"':'@"正在播放栏"','@"Queue & devices"':'@"播放队列与设备"','@"Lock screen widget"':'@"锁屏小组件"','@"Player"':'@"播放器"',
'@"Off"':'@"关闭"','@"On"':'@"开启"','@"Cancel"':'@"取消"','@"OK"':'@"好"','@"Remove"':'@"移除"','@"Save"':'@"保存"','@"Reset"':'@"重置"','@"Download"':'@"下载"','@"Retry"':'@"重试"',
'@"Accent colour"':'@"强调色"','@"Pick a colour"':'@"选择颜色"','@"Spotify’s green"':'@"Spotify 绿色"','@"Spotify\'s green"':'@"Spotify 绿色"','@"AMOLED background"':'@"AMOLED 黑色背景"',
'@"Gradient"':'@"渐变"','@"Show"':'@"显示"','@"Colour"':'@"颜色"','@"Strength"':'@"强度"','@"Height"':'@"高度"','@"Library"':'@"音乐库"','@"Playlists"':'@"播放列表"','@"Album"':'@"专辑"','@"Artist"':'@"艺人"','@"Home"':'@"主页"','@"Home & Library"':'@"主页与音乐库"','@"Hide on Home"':'@"在主页隐藏"',
'@"Navbar"':'@"导航栏"','@"Add a Tab"':'@"添加标签页"','@"Add"':'@"添加"','@"Name"':'@"名称"','@"Customize"':'@"自定义"','@"Choose a Link"':'@"选择链接"','@"Choose an Icon"':'@"选择图标"','@"Custom link"':'@"自定义链接"','@"Can\'t use that link"':'@"无法使用该链接"','@"Use Spotify\'s order"':'@"使用 Spotify 的排序"',
'@"Sources"':'@"来源"','@"Translation language"':'@"翻译语言"','@"Line meanings"':'@"逐行释义"','@"Karaoke"':'@"卡拉 OK"','@"Voice model"':'@"人声模型"','@"Download voice model"':'@"下载人声模型"','@"Remove voice model"':'@"移除人声模型"','@"Cancel download"':'@"取消下载"','@"No model"':'@"无模型"','@"Download failed"':'@"下载失败"','@"Not downloaded"':'@"未下载"','@"Checking…"':'@"正在检查…"',
'@"Privacy & clutter"':'@"隐私与精简"','@"Privacy"':'@"隐私"','@"Clutter"':'@"界面精简"','@"Tips"':'@"提示"','@"Tooltips"':'@"工具提示"','@"Vibrations"':'@"振动"','@"Controls"':'@"控制项"',
'@"Audio effects"':'@"音频效果"','@"Effects"':'@"音效"','@"Preset"':'@"预设"','@"Crossfeed"':'@"串音"','@"Room"':'@"房间"','@"Script"':'@"脚本"','@"Drive"':'@"驱动"','@"Width"':'@"宽度"','@"Release"':'@"释放时间"',
'@"Live Activity"':'@"实时活动"','@"Labs"':'@"实验室"','@"All flags"':'@"全部旗标"','@"Updates"':'@"更新"','@"Licenses"':'@"许可证"','@"Welcome tour"':'@"欢迎导览"','@"Export settings"':'@"导出设置"','@"Import settings"':'@"导入设置"','@"Reset all settings"':'@"重置所有设置"','@"Mod"':'@"插件"',
'@"Player screen"':'@"播放器页面"','@"Artwork background"':'@"封面背景"','@"Hide cards below the player"':'@"隐藏播放器下方卡片"','@"Hide on the player"':'@"在播放器中隐藏"','@"Bottom sheets"':'@"底部弹出面板"','@"Queue"':'@"播放队列"',
'@"Header"':'@"标题栏"','@"Hide in the header"':'@"在标题栏中隐藏"','@"Photo"':'@"照片"','@"Tabs"':'@"标签页"',
}
paths=[]
for p in (R/'tweak/Sources').rglob('*'):
 if p.suffix in {'.m','.x'} and ('Settings' in p.name or p.name in {'Pages.m','FlagPages.m','FlagsPage.m','AboutSettings.m','Backup.m','Licenses.m','UpdatePage.m'}): paths.append(p)
for p in paths:
 s=p.read_text(); old=s
 for a,b in M.items(): s=s.replace(a,b)
 if s!=old:p.write_text(s)
print('files=',len(paths),'replacements=',sum(1 for p in paths if p.read_text()))
