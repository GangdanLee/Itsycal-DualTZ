# 项目分期实施路线图与测试清单（ROADMAP）

- **开源仓库**：`https://github.com/GangdanLee/Itsycal-DualTZ`
- **当前状态**：**Phase 1–4 及北京时间默认化、双语热切换、P0/P1 体验升级已全部完成**（通过 Debug/Release 双配置编译、7 项端到端回归断言及像素级视觉核验，并与原版 `/Applications/Itsycal.app` 完全隔离共存）。

---

## 一、 分期交付计划

### Phase 1：工程底座隔离 + 自定义多时区菜单栏 + 双今标 + 日程双时区 + 拖拽缩放修复（已完成 ✅）
**目标**：产出首个可日常并排使用的可用版本，解决菜单栏看北京、弹窗主视觉、月历三态双今标、日程双时区四大核心需求。
- [x] 配置 Xcode Target 独立 Bundle ID（`com.morgan.ItsycalDualTZ`）与应用名 `Itsycal DualTZ`。
- [x] 剥离 Sparkle 自动更新入口；实现原版偏好设置首次启动安全导入（保留用户周一首日、周末高亮、周数、字号及已选日历源）。
- [x] 配置 Objective-C 与 Swift 混编 Bridging Header，建立 `Itsycal/DualTZ/` 目录。
- [x] 实现 `TimeZoneService.swift`、`DualClockFormatter.swift`、`BeijingHeroHeaderView.swift`、`DualTZBridge.swift`。
- [x] 修复拖拽缩放不回缩与窄窗时间数字截断问题：重构 `BeijingHeroHeaderView` 垂直刚性约束（`>= 940 > NSLayoutPriorityWindowSizeStayPut`），时间标签设置水平抗压缩 `999` 与响应式紧凑日期。
- [x] 扩展 `MoCalCell` 与 `MoCalendar` 实现三态纯视觉双今标（北京今日蓝框+淡蓝底、美西今日空心细框、点选日无描边纯底色）。
- [x] 改造 `AgendaViewController`、`AgendaPopoverVC`、`TooltipViewController`，在非全天日程旁以灰·蓝富文本附注北京时间，全天事件严格隔离。
- **阶段验收**：真机无头窗口 6↔10 行缩放误差 `0.0pt`，小/中/大三档无时间数字裁切。

### Phase 2：农历节气 + 中美法定假日与调休 JSON + 按北京时间新建日程（已完成 ✅）
**目标**：补全跨境运营日历标注与跨时区排会闭环录入能力。
- [x] 实现 `HolidayLunarService.swift`：离线农历、二十四节气、美国 11 项联邦假日（含 Observed 顺延）、感恩节/黑五/网一计算。
- [x] 内置 `BundledChinaHolidays.json`（2025–2027 年 106 条国务院放假与周末调休补班），实现 `ChinaHolidayStore.swift`（8s/12s 超时在线同步与 JSON Schema 校验 + 本地 JSON 导入）。
- [x] 升级 `Sizer.h/.m` 与 `MoCalGrid.h/.m` 支持 `cellWidth` / `cellHeight` 分离与小中大三档自适应布局，扩展 `MoCalCell` 绘制单行副标题与右上角无底框 `休`/`班`/`US` 微标，`TooltipViewController` 支持顶部节假日摘要。
- [x] 改造 `EventViewController.m`，增加 `[美西时间 | 北京时间]` 分段开关、实时跨时区换算回显与 `EKEvent.timeZone = Asia/Shanghai` 写入（勾选全天自动禁用时区开关）。
- **阶段验收**：通过 2025–2027 调休、黑五/网一、小/中/大三档零重叠、畸形 JSON 容错与按北京时间新建日程验证。

### Phase 3：默认隐藏的可选排会时间轴 + DST 7天预警条（已完成 ✅）
**目标**：强化跨国排会与季节性夏令时切换保障能力，并默认隐藏不常用组件以保持主界面极简。
- [x] 实现 `TimeScrubberView.swift` 与 `ScrubberTrackView.swift`（纯 AppKit 视图），由设置页开关 `kDualTZEnableTimeScrubber`（默认关闭）控制工具栏按钮显示与面板展开/折叠。
- [x] 联动 `MoCalendar.selectedDate` 动态计算目标日真实夏/冬令时偏移，绘制 24 小时三色作息重叠底轨，提供快捷时间与一键复制（无多余“京”字前缀）。
- [x] 实现 `DSTWarningBannerView.swift`：检测美西未来 7 天内夏/冬令时切换并支持按周期 `×` 忽略持久化。
- [x] 补全 `DualTZPrefsVC.swift` 全部 10 项开关与调休 JSON 同步入口，并完善 `ViewController.m` 互斥约束与 KVO 刷新。
- **阶段验收**：`2026-11-18`（PST `16h`）与 `2027-03-15`（PDT `15h`）滑块换算准确；默认隐藏态及全展开态 6↔10 行缩放误差均 `0.0pt`。

### Phase 4：全量边界回归、签名打包与交接（已完成 ✅）
**目标**：完成规范检查、Release 打包签名并交付使用。
- [x] 完成全部 `Itsycal/DualTZ/*.swift` 文件 `< 300` 行、单函数 `< 50` 行、零调试输出检查。
- [x] 编译 `Release` 构建，同步至 `dist/Itsycal DualTZ.app` 并执行 `--identifier com.morgan.ItsycalDualTZ` 稳定标识签名。
- [x] 重启定制版 `Itsycal DualTZ.app` 并验证与 `/Applications/Itsycal.app`（未修改）并行隔离；如需开机固定安装，可将 `dist/Itsycal DualTZ.app` 拖入 `/Applications`（或由后续自签证书固定 TCC）。

---

## 二、 核心边界与自动化测试用例清单

| 用例编号 | 测试维度 | 输入 / 场景条件 | 预期断言 | 结果 |
| :--- | :--- | :--- | :--- | :--- |
| TC-01 | 跨天临界点（冬令时） | LA `2026-11-17 07:59:59 PST` | 北京时间为 `2026-11-17 23:59:59`；`{diff}` 输出为空；双今标重合于 17 日。 | 通过 ✅ |
| TC-02 | 跨天临界点（冬令时） | LA `2026-11-17 08:00:00 PST` | 北京时间为 `2026-11-18 00:00:00`；`{diff}` 输出 `+1d`；`{diff_cn}` 输出 `次日`；月历 17 日空心细框、18 日蓝框+淡蓝底。 | 通过 ✅ |
| TC-03 | 跨天临界点（夏令时） | LA `2027-06-15 08:59 PDT` vs `09:00 PDT` | `08:59` 同日；`09:00` 跨日（`+1d`）。 | 通过 ✅ |
| TC-04 | 美西春令跳变日 | `2027-03-14`（01:59 PST 下一分钟为 03:00 PDT） | 时差平滑由 `16h` 变为 `15h`，不出现卡死或负差值。 | 通过 ✅ |
| TC-05 | DST 7天预警触发 | 系统日期设在跳变前第 7 天与第 8 天 | 第 8 天隐藏横幅；第 7 天显示提醒条；点 `×` 后同周期不再重复弹出。 | 通过 ✅ |
| TC-06 | 全天事件隔离 | 新建或展示全天事件 | `EventViewController` 勾选全天自动禁用时区切换并保持 `timeZone = nil`，Agenda 不附注北京时间。 | 通过 ✅ |
| TC-07 | 单元格布局极值 | `劳动节` + `休` + 3 个日程圆点 + 北京蓝框（小/中/大三档） | 公历数字、副标题、右上角微标、底部 3 圆点均清晰可见，无裁切或像素重叠。 | 通过 ✅ |
| TC-08 | 周数与起始日联动 | 保留并导入原版 `WeekStartDOW` 与外观设置 | 表头星期顺序、单元格对齐及已选日历源完整保留并刷新。 | 通过 ✅ |
| TC-09 | JSON 同步容错 | 注入 5 类畸形/空数组/非法日期/非布尔 JSON 载荷 | `parseAndValidate` 抛出 Schema 异常，已加载的 106 条节假日数据不受影响。 | 通过 ✅ |
