# BiliMusic 改进建议（10 条，均已在模拟器 + 真机验证）

> 这些改动来自一次实际调试：在模拟器（720x1280 / Android）上逐条复现、修改、验证，release 包实机复测。
> 全部为增量改动：**12 个文件修改（+542 / −94）、4 个文件新增（1025 行）**，`flutter analyze` 无新增告警。

| # | 问题 | 类型 | 改动量 |
|---|------|------|--------|
| 1 | 点底部导航「搜索」自动弹输入法 | 体验瑕疵 | 1 行 |
| 2 | 搜索页左上角返回箭头冗余 | 体验瑕疵 | 删除 5 行 |
| 3 | 搜索页默认是空状态，浪费一屏 | 功能建议 | 新增 2 文件 656 行 + 接口 191 行 |
| 4 | 歌单页「添加到播放列表」是空实现 | **功能性 Bug** | 4 文件 +38 行 |
| 5 | 搜索结果页返回必重载 | **功能性 Bug** | 2 文件 +95 行 |
| 6 | 搜索页往下浏览，搜索框钉在顶部 | 体验瑕疵 | 2 文件 |
| 7 | 迷你播放条点标题区域没反应 | 交互不一致 | 1 处 |
| 8 | 播放列表面板点空白处关不掉 | **功能性 Bug** | 1 处 |
| 9 | 输入法弹出时迷你播放条被顶起 | 体验瑕疵 | 1 处 |
| 10 | 搜索没有历史记录，也没有独立搜索入口 | 功能建议 | 新增 2 文件 320 行 |

---

## 1. 点底部导航「搜索」，输入法自动弹出

**现象**：从首页切到搜索标签，焦点自动落在搜索框并弹出软键盘，但用户此时只想看一眼排行榜/历史，不想输入。

**原因**：`search_overlay.dart` 里 `autoFocus: !_hasInitialQuery` —— 无初始关键词时为 `true`。

**建议**：`autoFocus: false`。底部导航进入本页的场景下自动聚焦没有收益，反而遮挡半屏。

```dart
// lib/features/search/ui/search_overlay.dart
SearchBarWidget(
  controller: _searchController,
  onSearch: _submitSearch,
  autoFocus: false, // 不做自动聚焦：点底部导航「搜索」时不应该弹输入法
  hintText: '搜索音乐、视频、用户...',
),
```

---

## 2. 搜索页左上角返回箭头冗余

**现象**：搜索页顶部左上一个返回箭头，点了只是 `ShellPageManager.instance.pop()` 回首页 —— 但底部导航本身就在，Tab 级页面出现返回键属于层级混乱（Material 规范：底部导航的顶级页面不放返回键）。

**建议**：删掉该 `IconButton`。

> 注意：`search_results_overlay.dart`（结果页）的返回箭头**要保留** —— 该页底部导航被隐藏（`_showBottomBar` 只对 home/search/profile/settings 为真），没有返回键会变死路。

---

## 3. 建议把搜索页默认内容改成「音乐热歌榜」

**现状**：默认屏是空状态 + 5 个建议词（周杰伦/林俊杰/…），用户 80% 的时间在搜索框里打字，这一屏完全浪费。

**建议**：直接铺 `bilibili.com/v/popular/music` 那个**热歌榜**——每期 20 首，点任意一行就把整期 20 首放进播放列表并从这首开始播。等于把「发现」入口前移到搜索 Tab。

### 3.1 先说要避开的一个坑

`v/popular/rank/music` 页面上的「排行榜」其实有**两套完全不同的数据**，第一版实现踩错了：

| | A. 视频区排行 | B. 音乐热歌榜（本次采用） |
|---|---|---|
| 接口 | `/x/web-interface/ranking/v2?rid=3&type=all` | `/x/copyright-music-publicity/toplist/music_list?list_id=<期>&list_type=1` |
| 条目 | 普通投稿视频，整榜 97 条 | **歌曲**，每期固定 20 首 |
| 点开 | 播这个视频 | 播挂在这首歌下的**二创投稿视频**（歌本身没有音频流） |
| 换期 | 无（`type` 参数已失效，见附录） | 有，257 期可切 |

A 也能用（返回标准 archive 字段，直接喂 `Music.fromArchiveJson`），但它语义是「音乐区投稿热榜」，和网页上那个带「10月16日 第227期」的榜单不是一回事。B 才是网页版看到的那个。

### 3.2 热歌榜接口（实测结论）

```http
# 1) 期数索引：按年份分桶返回，本文件里拍平后按 list_id 倒序
GET https://api.bilibili.com/x/copyright-music-publicity/toplist/all_period?list_type=1

# 2) 某一期：固定 20 条
GET https://api.bilibili.com/x/copyright-music-publicity/toplist/music_list?list_id=441&list_type=1
```

- `list_type=1` 热歌榜（`list_id` 为**奇数**）；`list_type=3` 二创榜（偶数 id）。两者字段结构一致。
- `all_period` 的 `data` 是 `{"2026": [{ID, priod, publish_time}, …], "2025": […]}` 这种按年分桶的 map，**注意官方的 key 拼写就是 `priod`**（typo，别当 bug 修）。
- `music_list` 的 20 条是**扁平字段**，关键几个：
  - `music_title` / `singer` / `album` / `heat` / `rank` / `last_rank` —— 歌曲本身的信息；
  - `creation_bvid` / `creation_first_cid` / `creation_title` / `creation_nickname` / `creation_up` / `creation_duration` / `creation_cover` —— **真正能播的那个二创视频**；
  - ⚠️ `creation_cover` 返回的是 `http://`，必须改成 `https://`，否则 Android 9+ 明文流量被禁，封面全白；
  - ⚠️ 歌曲本身**没有音频流**（`/x/copyright-music-publicity/music/playurl` 之类不存在），只能播 `creation_*` 指向的投稿——这也解释了为什么 B 站网页版这个榜每条下面都挂着一个视频。

### 3.3 三个交互细节

1. **点任意一行 = 整期入队**：`addAllToPlaylist(20 首)` → `playMusic(点的那首)`。队列按 `(bvid, cid)` 去重，所以重复点同一期只会补缺的，提示语用**实际增量**（`playlistLength` 前后差）而不是「已添加 20 首」。
2. **右上角期数切换**：头部右侧放 `10月16日 第227期 ⌄`，点开底部弹层（62% 高、每行 52px、自动滚到当前期），选一期就 `invalidate` 数据源并清掉选中态回到最新期。
3. **下拉刷新保持所选期**：`RefreshIndicator` 重拉的是**当前选中那期**，不能借刷新把用户选的期悄悄变回最新——这是最容易漏的一处。

> 队列是「追加」不是「替换」：用户此刻可能正在听别的歌，整期入队不该打断播放。

### 3.4 实现

- `lib/domain/music_toplist.dart`（新增 147 行）：`MusicToplist` / `MusicToplistSong` / `MusicToplistPeriod`，负责把扁平字段装配成现有 `Music` 模型（`id`=creation_bvid、`cid`=creation_first_cid、`artist`=creation_nickname），派生 `dateLabel`(`2026.10.16`) / `periodLabel`(`第227期`) / `chipLabel`(`10月16日 第227期`)。
- `api_service.dart` 新增 `fetchMusicToplistPeriods()` 与 `fetchMusicHotToplist({listId, listType})`（**不用 `FutureProvider` 链式依赖，一次拿期数+当期的组合，减少一次往返**）。
- `search_providers.dart`：`musicToplistPeriodsProvider`、`selectedToplistIdProvider`（Riverpod 3 已移除 `StateProvider`，用最小 `Notifier<int?>` 代替）、`musicHotToplistProvider`（watch 选中期，**故意不 autoDispose**，切 Tab 回来不重拉）。
- 新增 `lib/features/search/ui/search_rank_page.dart`（509 行）：名次徽标（前三红/橙/黄 + ↑↓ 涨跌）+ 封面 + 两行视频标题 + `UP主 - 时长` + 播放图标；下拉刷新、期数切换器、加载态、失败重试。

### 3.5 验证

模拟器：进搜索 Tab → 显示「音乐热歌榜 / 第227期」20 行 → 点第 3 行 → 提示「已把这一期 20 首放入播放列表」且播放条开始走（logcat `state=3 PLAYING`）→ 切换第 226 期，列表整体换掉、副标题跟着变 → 下拉刷新仍是 226 期 → 再点一行，队列只在原基础上补进缺的曲子。

如果作者觉得 509 行的默认页偏重，退一步可以只做「空状态里放一张『音乐热歌榜』入口卡」，同一个 provider 复用。

---

## 4. 【Bug】歌单页「添加到播放列表」按钮点了没反应

**现象**：任意歌单页（含搜索进入的合集/多P视频）中部三个按钮：`播放全部` / `随机播放` / **`添加到播放列表`** / `收藏`。点「添加到播放列表」毫无反应。

**原因**：`playlist_hero.dart` 里它是空实现：

```dart
onPressed: hasSongs ? () {} : null,   // ← 空闭包，按钮是活的但什么都不做
```

**建议**：把队列追加能力接进来。队列已有 `addAllToPlaylist()`（按 `(id, cid)` 去重），只是一直没人调用。

```dart
// lib/features/playlist/playlist_page.dart
Future<void> _addAllToPlaylist() async {
  if (_songs.isEmpty) return;

  final service = ref.read(playlistServiceProvider);
  final before = service.playlistLength;

  await ref.read(playlistCommandsProvider.notifier).addAllToPlaylist(_songs);

  final added = service.playlistLength - before;   // 用「实际增量」而不是总数
  if (!mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(added > 0
          ? '已添加 $added 首到播放列表'
          : '这 ${_songs.length} 首已经在播放列表里了'),
      duration: const Duration(seconds: 2),
    ));
}
```

配套：`PlaylistHero` / `PortraitPlaylistPage` / `LandscapePlaylistPage` 各加一个 `VoidCallback? onAddToPlaylist` 透传（4 个文件、每处 1~3 行）。

**为什么用增量做提示**：队列是去重的，99 首合集里已播过的会被跳过。直接报「已添加 99 首」会和实际队列不符，用户会以为 bug。

**验证**：搜索「邓紫棋」→ 打开 99P 合集 → 点「添加到播放列表」→ 提示「已添加 99 首到播放列表」，队列确实变长 99；重复点第二次提示「已经在播放列表里了」。

**顺带**：同一排的「更多（…）」也是 `onPressed: () {}`，建议一并实现或先隐藏。

---

## 5. 【Bug】从歌单/详情返回搜索结果页，整个搜索重跑一遍

**现象**：搜索结果页 → 点进某个视频合集 → 返回，结果页变成「搜索中…」转圈，重新发请求、重新渲染，**滚动位置归零**。同一关键词两次请求返回的条目数甚至可能不同（实测 系列视频 4 → 3、单曲 16 → 17），所以用户看到的是「内容变了」，非常伤。

**根因（架构级，值得注意）**：

`ShellPageManager` 不是 `Navigator` 栈，而是自建的 `ShellPageEntry` 列表 + 壳层里的 `AnimatedSwitcher`，key 为 `ValueKey(page.name)`。push 歌单页时，搜索结果页这一帧被 `AnimatedSwitcher` **卸载并 dispose**；pop 回来时又是一次全新 build → `initState` 重跑 → 里面那个 `addPostFrameCallback(_performSearch)` 再次发请求。

所以这不是搜索结果页独有的问题：**任何把数据存在 State 里、又在 initState 里请求的非 playlist 页面，进出一次都会被重建一次**。建议作者在架构层二选一：

1. 壳层用 `IndexedStack`/`Offstage` 保活页面帧（改造成本低，但要处理导航参数随帧不串用的问题——作者已经在 `ShellPageEntry` 里解决过了）；
2. 或者按下面的「快照」模式，让页面数据活得比 State 久。

**本次采用的方案（快照，改动最小）**：

```dart
// lib/features/search/search_providers.dart
class SearchSnapshot {
  SearchSnapshot(this.query);
  final String query;
  List<SearchResult> results = const [];
  List<SearchResultType> availableTypes = const [];
  final Map<String, List<Page>> pages = {};   // 分P预取缓存，与页面共享同一个 Map 实例
  SearchResultType selectedType = SearchResultType.video;
  double scrollOffset = 0;
  bool get hasData => results.isNotEmpty;
}

class SearchCache {                       // 按 query 建条目，LRU 最多 8 条
  final Map<String, SearchSnapshot> _entries = {};
  SearchSnapshot of(String query) { /* remove + 重新插入，超出淘汰最旧 */ }
}

final searchCacheProvider = Provider<SearchCache>((ref) => SearchCache());
```

```dart
// lib/features/search/ui/search_results_overlay.dart —— initState
_snapshot = ref.read(searchCacheProvider).of(widget.query);
_allResults = _snapshot.results;
_pagesCache = _snapshot.pages;              // 共享引用：页面里的写入天然留在快照里
_availableTypes = _snapshot.availableTypes;
_selectedType = _snapshot.selectedType;
_scrollController.addListener(() => _snapshot.scrollOffset = _scrollController.offset);

if (_snapshot.hasData) {
  _hasSearched = true;                       // 命中快照：不请求、不转圈
  _filteredResults = SearchResult.filterByType(_allResults, _selectedType);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _restoreScroll();                        // 恢复滚动位置
    _fetchAllPagesWithDelay(_allResults);    // 只补抓还没抓到的分P
  });
} else {
  WidgetsBinding.instance.addPostFrameCallback((_) => _performSearch(widget.query));
}
```

要点：

- 命中快照时**连隐藏成本也省了**：原本每次返回都会把 20 个视频的分P再预取一遍（每个 `getVideoPages` 一次请求），现在只补缺。
- 选中 Tab（单曲/系列视频/…）和滚动位置一并恢复，返回后视觉上完全连续。
- 结果为空**不写**快照，下次进来仍会重试（避免把「网络失败」永久缓存）。

**验证**：搜索「邓紫棋」→ 滚到「单曲」区 → 点开合集 → 返回：无转圈、无请求、列表内容与条目数不变、滚动位置还在原处（改前必现「搜索中…」+ 回顶）。

---

## 6. 搜索页往下浏览，搜索框该跟着滑走

**现象**：搜索 Tab 顶部搜索栏是 `Column` 的第一个子项、内容区在下面 `Expanded`，所以用户滚榜单时搜索框永远钉在顶部，一屏白占 60+ px。

**建议**：把搜索栏当成「滚动内容的第 0 项」，交给内容的 sliver 一起滚。实现上就是给内容页一个 `header` 参数，不要 pinned、不要 floating：

```dart
// search_overlay.dart
final searchHeader = Padding(
  padding: EdgeInsets.fromLTRB(isDesktop ? 0 : 16, 16, isDesktop ? 0 : 16, 0),
  child: SearchBarWidget(controller: _searchController, onSearch: _submitSearch, autoFocus: false),
);
return Scaffold(body: SafeArea(child: SearchRankPage(header: searchHeader)));
```

```dart
// search_rank_page.dart —— 三个状态（loading / error / data）统一走同一个壳
Widget buildScroll({required List<Widget> slivers}) => RefreshIndicator(
  onRefresh: () async => ref.refresh(musicHotToplistProvider.future),
  child: CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [if (header != null) SliverToBoxAdapter(child: header), ...slivers],
  ),
);
// data 分支：SliverPadding(horizontal) > SliverList.builder（第 0 项是榜单小标题）
// loading/error 分支：SliverFillRemaining(hasScrollBody: false, child: …)
```

要点：`loading`/`error` 也要包在同一个 `CustomScrollView` 里，否则加载态一出现搜索框就「跳」回顶部再消失，视觉上像闪。

---

## 7. 迷你播放条：点标题区域应该和点封面一样进播放页

**现象**：迷你播放条只有左边的封面挂了 `onTap: onExpand`，中间 2/3 的标题/UP 主区域点下去毫无反应——而这恰好是用户最容易点的位置。

**建议**：把 `_buildSongInfo(...)` 整个用 `GestureDetector` 包住，`behavior: HitTestBehavior.opaque`（标题是 `Text`，不加 opaque 会漏掉文字间的空白）：

```dart
Expanded(
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onExpand,
    child: _buildSongInfo(textPrimary, textSecondary, currentPlayerState),
  ),
),
```

右侧的播放/暂停、播放列表按钮各有自己的 `GestureDetector`，不会被这层抢走。

---

## 8. 【Bug】播放列表面板：点上半部分空白处关不掉

**现象**：点迷你条右侧的播放列表按钮弹出「播放列表」面板，只有系统返回键能关；点面板上方那条半透明空白区没反应，和用户预期（点外部关闭）不符。

**根因**：`PlaylistSheet` 内部用 `DraggableScrollableSheet`（`initialChildSize: 0.5`），它**会把自己撑到整屏高度**再靠 `Align(bottomCenter)` 把内容压到下半屏。于是 `showModalBottomSheet` 的 modal barrier 被这层全高 widget 挡在身后，barrier 永远收不到点击 —— `isDismissible` 默认 true 也没用。

**建议**：既然 `DraggableScrollableSheet` 不能用 `Align` 缩小命中区，就在它下面垫一层可点的透明背板：

```dart
// lib/features/playlist/widgets/playlist_sheet.dart
child: Stack(
  children: [
    Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),   // 点空白处收起
        child: const SizedBox.expand(),
      ),
    ),
    DraggableScrollableSheet(initialChildSize: 0.5, minChildSize: 0.25, maxChildSize: 0.9, …),
  ],
),
```

用 `maybePop()` 而不是 `pop()`：面板可能已随路由一起出栈，`pop()` 会抛。

**验证**：播放任意一首 → 点右侧播放列表图标 → 面板弹出 → 点上方空白处 → 面板收起；面板内滚动、拖拽手柄、上下拖拽缩放均不受影响。

---

## 9. 输入法弹出时迷你播放条被键盘顶上去

**现象**：搜索页点搜索框、键盘升起时，底部迷你播放条跟着上移贴在键盘上缘，列表被挤得更短。

**期望**：键盘直接盖住它就完事（B 站 App 就是这样），输入框区域不要被继续挤压。

**原因**：`Scaffold` 默认 `resizeToAvoidBottomInset: true`，键盘高度会压缩 `body`，底部的迷你条自然被推上去。

**改法**：外壳的两个 `Scaffold`（手机 / 平板分支）都加 `resizeToAvoidBottomInset: false`。

```dart
Scaffold(
  resizeToAvoidBottomInset: false, // 键盘只盖住底部，不压缩页面
  body: ...,
  bottomNavigationBar: ...,
)
```

**验证**：点搜索框 → 键盘升起 → 迷你播放条停在原位（被键盘遮住），列表不再变矮。

---

## 10. 搜索入口：悬浮搜索层（点搜索框 → 盖在榜单上，返回键直接关）

**诉求**：搜索页默认是热歌榜，搜索不该占页面；点搜索框弹出一层「悬浮搜索」，上面是真输入框 + 搜索历史，系统返回键/点空白处一下关掉，回到榜单。

**做法**：搜索栏从「真 `TextField`」降级为「外观按钮」，真输入框只活在一个新 push 的透明路由里。

```dart
// 1) 榜单页的搜索框：只是个长得像输入框的按钮
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => showSearchOverlayPanel(context), // push 透明路由
  child: IgnorePointer(                        // 永远拿不到焦点
    child: SearchBarWidget(controller: _c, onSearch: (_) {}, autoFocus: false),
  ),
)

// 2) 悬浮层：透明路由 + 自绘遮罩 + 顶部悬浮卡片
Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
  opaque: false, barrierColor: Colors.transparent,
  pageBuilder: (_, __, ___) => const SearchOverlayPanel(),
));
// Scaffold(resizeToAvoidBottomInset: false)
//   ├─ Positioned.fill(GestureDetector(onTap: pop, child: Container(Colors.black54)))
//   └─ Positioned(top: safeTop + 10, ... ConstrainedBox(maxHeight: 屏高 − 键盘高 − safeTop − 24)
//        └─ Material(圆角 20 + elevation 12) ─ SearchBarWidget(autoFocus: true) + 历史胶囊
```

**为什么用路由而不是「在当前页面插一块历史面板」**

- 路由天然有返回栈，系统返回键 / 返回手势 / 侧滑就是 pop，不用自己接管 `PopScope`；
- 输入框从「页面的一部分」变成「独立路由的根」，父节点不会随页面状态变化而重排 —— 这一步顺便消灭了一个很坑的 bug：`TextField` 一旦被搬到另一个父节点下，Element 会按位置重建，`TextInputConnection` 断开，**键盘闪一下就自己收起**（历史记录也因此一闪而过）；
- 键盘高度自己算（`viewInsets.bottom`）+ 卡片 `ConstrainedBox` 限高，历史条数多时卡片内部滚动，不会顶到状态栏。

**两个平台细节**

- Android 的输入法会先吃掉一次返回键用于收键盘，所以「键盘开着时按返回」是：第一次收键盘、第二次关层；点遮罩空白处则是一下即关。
- 卡片内部不要再放 `SafeArea`，高度由外部 `viewInsets` 计算，否则键盘弹起时卡片会二次上移。

**验证**：点搜索框 → 悬浮卡片 + 键盘升起、榜单被压暗仍可见 → 点遮罩/连按返回都能关 → 点历史胶囊直接出结果并记入历史 → 长按胶囊删单条、「清空」弹确认 → 从结果页返回仍在榜单页（搜索框不聚焦、无键盘）。

---

## 附 A：B 站音乐类榜单接口横向对比（实测）

| 用途 | 接口 | 备注 |
|---|---|---|
| 本期热歌榜 | `/x/copyright-music-publicity/toplist/music_list?list_id=<期>&list_type=1` | **推荐**，固定 20 首，带二创视频字段 |
| 期数索引 | `/x/copyright-music-publicity/toplist/all_period?list_type=1` | 257 期，按年分桶，key 拼作 `priod` |
| 音乐区投稿热榜 | `/x/web-interface/ranking/v2?rid=3&type=all` | 97 条；`type` 传 `all`/`origin`/`rookie` 结果**完全一致**，`new`/`weekly`/`hot` 直接 −400；无分页 |
| 其它分区 | 同上，改 `rid`：0 全站 100 / 1 动画 / 4 游戏 / 36 知识 / 119 鬼畜 / 129 舞蹈 / 155 时尚 / 160 生活 / 168 国创 / 177 纪录片 / 181 影视 / 188 科技 / 211 美食 / 217 动物圈 / 223 汽车 / 234 运动 | `rid=13`（番剧）/`202`/`33`/`203` 返回 −400，番剧走 PGC 另一套 |
| 番剧/影视榜 | `/pgc/season/rank/web/list?season_type=1&day=3` | 1 番剧 99 / 2 电影 100 / 3 纪录片 100 / 4 国创 99 / 7 综艺 100，返回 `season` 字段需另一套模型 |
| 综合热门 | `/x/web-interface/popular?ps=20&pn=1` | 有 `no_more` 可翻页 |
| 入站必刷 | `/x/web-interface/popular/precious` | 98 条 |
| 每周必看 | `/popular/series/list` + `/popular/series/one?number=N` | 394 期 / 单期 49 条 |
| ❌ 已失效 | `/x/web-interface/ranking/index?day=3`（只 8 条）、`/x/web-interface/ranking/region?rid=3&day=3`（只 11 条）、`/pgc/web/rank/list`（`data:null`） | 别再用 |

## 附 B：风控（`-352`）排查提示

调试 B 站接口时建议先确认 `buvid3` 是否带上。`-352` 会让排查方向跑偏到「接口改了」，实际只是风控。本项目 `BiliClient` 已自动从 `/x/frontend/finger/spi` 取 buvid，线上无影响；裸脚本手试接口时需要自己补，且请求间隔 ≥3~5s，密集请求同样会触发。

## 附 C：一条与本仓库无关但踩到的坑

`keytool`/Gradle 的 release 签名走环境变量（`KEYSTORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`）+ 本地 `android/app/keystore.jks`（已在 `.gitignore` 里）。想在本机出 release 包必须先自己生一份 keystore，否则 `flutter build apk --release` 会在 signingConfig 阶段失败。debug 包能装不代表 release 能出包。
