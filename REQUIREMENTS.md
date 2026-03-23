# 待办事项页面 — 优化需求文档

> 源文件：`todo-share/index.html`
> 测试日期：2026-03-24
> 测试方法：多角色模拟（老板/股东/副总/业务骨干）

---

## 一、需求总览

| 分类 | 需求数 | 高优先 | 中优先 |
|------|--------|--------|--------|
| 数据架构 | 1 | 1 | 0 |
| 功能缺失 | 7 | 4 | 3 |
| UX 优化 | 6 | 2 | 4 |
| 数据安全 | 3 | 3 | 0 |
| Bug 修复 | 2 | 1 | 1 |
| **合计** | **19** | **11** | **8** |

---

## 二、详细需求

### 🔴 P0 — 必须改（影响核心使用）

#### REQ-01 多人实时协同 + 数据同步 ⚡ 最紧急

**发现人**：老王

**问题**：数据只存在 `localStorage`（浏览器本地存储），不同终端/浏览器之间完全隔离。A 终端勾选了"已完成"，B 终端打开还是"待完成"。本质上是 **单机工具，不是团队工具**。

**根因分析**：
```
当前架构：
  终端A (localStorage) ←→ index.html ←→ 终端B (localStorage)
         ↑ 各自独立，互不通信

目标架构：
  终端A ←→ Supabase 实时数据库 ←→ 终端B
              ↑ 唯一数据源
```

**需求描述**：
1. **共享数据层**：引入 Supabase（已有账号：`cmswoyiuoeqzeassubvw`），作为唯一数据源
2. **实时同步**：任何人勾选/修改任务，所有在线终端 < 1 秒内自动更新（Supabase Realtime）
3. **身份识别**：首次打开时选择身份（老王/凯哥/阿超/旁观者），不要求登录
4. **操作溯源**：每次状态变更记录谁在什么时间操作的（如"凯哥 3/24 10:30 完成了 #1"）
5. **离线兜底**：断网时操作存入 localStorage，恢复连接后自动同步（可选，v2 再做）

**Supabase 表结构设计**：

```sql
-- 会议/项目
CREATE TABLE meetings (
  id TEXT PRIMARY KEY,
  title TEXT,
  subtitle TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 待办任务
CREATE TABLE todos (
  id SERIAL PRIMARY KEY,
  meeting_id TEXT REFERENCES meetings(id),
  section_id TEXT,        -- 'hr', 'host', 'player', ...
  text TEXT NOT NULL,
  owner TEXT,             -- '老王', '凯哥', '阿超'
  tag TEXT DEFAULT '普通', -- '紧急', '普通'
  due_date TEXT,          -- '3/24', '3/31', '' 
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 任务完成状态（每条任务每人的状态独立）
CREATE TABLE todo_status (
  id SERIAL PRIMARY KEY,
  todo_id INT REFERENCES todos(id),
  user_identity TEXT,     -- '老王', '凯哥', '阿超'
  completed BOOLEAN DEFAULT false,
  note TEXT,              -- 完成备注
  completed_by TEXT,      -- 谁标记的
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(todo_id, user_identity)
);

-- 自定义新增任务
CREATE TABLE custom_todos (
  id SERIAL PRIMARY KEY,
  meeting_id TEXT REFERENCES meetings(id),
  section_id TEXT,
  text TEXT NOT NULL,
  owner TEXT,
  tag TEXT DEFAULT '普通',
  due_date TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  deleted BOOLEAN DEFAULT false
);

-- RLS 策略（所有人可读，登录后可写）
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read" ON todos FOR SELECT USING (true);
CREATE POLICY "Authenticated can write" ON todos FOR ALL USING (auth.role() = 'authenticated');
```

**改动范围**：
- **后端**：Supabase 建表 + RLS 策略 + 初始数据导入
- **前端 JS**：
  - 新增 `SupabaseClient` 初始化
  - `loadFromSupabase()` 替代纯本地 DATA
  - `toggleItem()` 改为 `updateTodoStatus(todoId, userId, completed, note)`
  - 订阅 `supabase.channel()` 实时变更推送
  - 身份选择 UI + localStorage 缓存
- **前端 HTML**：首次访问弹窗选择身份
- **数据迁移**：一次性脚本把现有 41 条任务导入 Supabase

**难度评估**：

| 步骤 | 难度 | 工时 |
|------|------|------|
| Supabase 建表 + 导入数据 | ⭐ | 20 分钟 |
| 前端 Supabase 连接 + 读取 | ⭐⭐ | 40 分钟 |
| 勾选完成 → 写回 Supabase | ⭐⭐ | 30 分钟 |
| Realtime 订阅 + 自动刷新 | ⭐⭐⭐ | 1 小时 |
| 身份选择 UI | ⭐ | 20 分钟 |
| 操作溯源（谁改的） | ⭐⭐ | 30 分钟 |
| **合计** | **⭐⭐⭐ (3/5)** | **约 3 小时** |

**技术风险**：
- Supabase Realtime 免费额度：500 并发连接，3 人使用绰绰有余
- 首次加载需等 Supabase 响应（约 200ms），可用 localStorage 做首屏缓存
- 手机端需确保 HTTPS 访问（Supabase 要求）

**预计工时**：3 小时（含测试）

---

#### REQ-02 逾期任务自动标红

**问题**：3/24 到期的 5 项紧急任务与 5 月的远期任务视觉上无区别，无法一眼识别当天要做什么。

**需求描述**：
- 读取系统当前日期，与任务 `date` 字段比较
- 已过期未完成 → 任务行左侧加红色竖条，文字颜色加深红
- 今天到期未完成 → 加橙色竖条 + "今天" 标签
- 今天到期已完成 → 绿色 ✓ 标记，不加紧迫感

**改动范围**：
- JS：新增 `getOverdueStatus(dateStr)` 函数，解析日期字符串与 `new Date()` 比较
- CSS：新增 `.todo-item.overdue`、`.todo-item.due-today` 样式（左侧 3px border）
- render 函数中调用判断，输出对应 class

**难度**：⭐ (1/5) — 纯前端日期比较，20 行代码

**预计工时**：15 分钟

---

#### REQ-02 "只看我的"快捷筛选

**问题**：每个执行人要看完自己负责的所有任务，需要在执行人筛选栏逐个点击，且当前筛选器状态管理不够直观。

**需求描述**：
- 在筛选栏执行人区域前加一个 **"👤 我的"** 按钮
- 点击后按预设的用户身份过滤（可硬编码默认身份，或首次访问时弹窗选择）
- 选中状态用用户名 + 头像色块显示，醒目
- 可配置：`localStorage` 存储 `myRole`，支持切换

**改动范围**：
- JS：新增 `myRole` 状态变量，`setMyRole(role)` 函数
- HTML：筛选栏增加"我的"按钮
- CSS：选中态样式

**难度**：⭐⭐ (2/5) — 需要新增状态管理 + UI 元素

**预计工时**：30 分钟

---

#### REQ-03 任务备注功能

**问题**：完成/未完成只有二选一，无法记录执行细节（如"已发，阿超确认收到"）。

**需求描述**：
- 每个任务项右侧（或展开区域）增加备注输入框
- 点击任务文本或备注图标可展开/收起备注区
- 备注内容存入 `localStorage`（`state[id+'_note']`）
- 已完成的任务显示备注摘要（截断 30 字，点击展开全文）

**改动范围**：
- HTML：todo-item 内新增 `.todo-note` 区块（默认隐藏）
- JS：`toggleNote(id)`、`saveNote(id, text)` 函数
- CSS：展开动画 + 备注区样式

**难度**：⭐⭐ (2/5) — 新增 DOM 元素 + localStorage 读写

**预计工时**：45 分钟

---

#### REQ-04 敏感信息脱敏

**问题**：薪资差异（主播 600 vs 教练 400）、劳动法规避策略等敏感内容对所有查看者可见，存在管理和法律风险。

**需求描述**：
- 对含有敏感关键词的任务自动脱敏显示（如"薪资"、"工资"、"底薪"、"绩效"、"劳动法"）
- 脱敏方式：文本替换为 `[涉及薪资信息，请登录查看]` 类占位符
- 提供"显示全部"开关（需输入简易密码或确认身份）
- 标记为敏感的任务行加 🔒 图标

**改动范围**：
- JS：新增 `sensitiveKeywords` 数组 + `maskText(text, showAll)` 函数
- HTML：header 区域增加"🔒 显示敏感信息"开关
- CSS：脱敏文本样式

**难度**：⭐⭐ (2/5) — 关键词匹配 + 文本替换，密码验证用简单 confirm 即可

**预计工时**：30 分钟

---

#### REQ-05 截止日期补全 + 空日期提醒

**问题**：41 项任务中有 18 项没有截止日期（占 44%），等于没有 Deadline 约束。

**需求描述**：
- 数据层：为所有无日期任务补充合理截止日期
- 页面层：无日期任务在标签区显示 "⚠️ 未设截止日"（灰色标签，不刺眼）
- 筛选器增加"⏰ 无截止日"选项

**改动范围**：
- DATA 数组：逐项补全 date 字段（纯数据修改）
- JS：render 中无日期时显示警告标签
- HTML：筛选栏增加无日期按钮

**难度**：⭐ (1/5) — 数据补全是体力活，代码改动极小

**预计工时**：数据补全 20 分钟 + 代码 10 分钟 = 30 分钟

---

### 🟡 P1 — 应该改（提升使用体验）

#### REQ-06 任务新增功能

**问题**：会议后想到新事项只能改源代码，无法在页面上直接添加。

**需求描述**：
- 页面底部或每个分类区域底部加 "+ 添加任务" 按钮
- 点击后弹出 inline 表单（任务描述、执行人、优先级、截止日期）
- 新任务存入 `localStorage`，与内置数据合并显示
- 内置数据不可删除，自建数据可编辑/删除

**改动范围**：
- JS：新增 `addTask(sectionId, taskObj)` 函数，render 时合并 `customTasks`
- HTML：每个 section 底部加按钮 + 弹出表单
- CSS：表单样式 + 添加按钮样式
- 数据结构：`localStorage` 新增 `customTasks` 对象

**难度**：⭐⭐⭐ (3/5) — 需要完整 CRUD 逻辑 + 表单验证 + 数据合并策略

**预计工时**：2 小时

---

#### REQ-07 任务完成度百分比（针对持续性任务）

**问题**：如"裁人 26→18"、"球杆库存消化"这类持续性任务只有完成/未完成，无法反映进度。

**需求描述**：
- 新增任务属性 `progress`（0-100 默认值）
- 有 progress 的任务显示迷你进度条（任务文本下方）
- 点击进度条可拖动调整
- section 统计从 "N/M 完成" 改为 "N/M 完成，总进度 X%"

**改动范围**：
- DATA：为持续性任务添加 `progress` 字段
- JS：render 中判断是否有 progress，有则渲染进度条 + 拖动事件
- CSS：迷你进度条样式（3px 高度，绿色渐变）
- localStorage 同步 progress 值

**难度**：⭐⭐⭐ (3/5) — 进度条交互 + 拖动事件处理 + 数据持久化

**预计工时**：1.5 小时

---

#### REQ-08 任务依赖关系可视化

**问题**："律师确认后才能推行改晚班" 这类依赖关系只存在于文字描述中，不可视。

**需求描述**：
- DATA 新增 `depends` 字段（`depends: [17]` 表示依赖任务 17）
- 被阻塞的任务显示 🔗 图标 + "等待: [任务名]" 标签
- 依赖任务未完成时，当前任务 checkbox 禁用（灰色 + hover 提示"请先完成前置任务"）
- 筛选器增加"🔗 被阻塞"选项

**改动范围**：
- DATA：为相关任务添加 depends 字段
- JS：`isBlocked(id)` 判断函数，render 中应用样式和禁用逻辑
- CSS：阻塞态样式（半透明 + 🔗 图标）

**难度**：⭐⭐⭐ (3/5) — 需要递归依赖检测 + UI 联动

**预计工时**：1.5 小时

---

#### REQ-09 "本周必须完成"视图

**问题**：老板需要快速看到本周关键路径，目前只能翻时间线对比任务列表。

**需求描述**：
- 筛选栏增加"📅 本周"快捷按钮
- 点击后自动筛选 date 在本周范围内的任务 + 所有紧急任务
- header 统计区切换为本周视角（本周 X 项，已完成 Y 项）

**改动范围**：
- JS：`getWeekRange()` 获取本周起止日期，`matchFilter` 增加本周逻辑
- HTML：筛选栏加按钮

**难度**：⭐⭐ (2/5) — 日期范围计算 + 筛选逻辑扩展

**预计工时**：30 分钟

---

#### REQ-10 删除确认 + 撤销机制

**问题**：删除操作不可逆，数据只存 localStorage，误删无法恢复。

**需求描述**：
- 删除后不立即移除，改为折叠显示 + 底部"已删除，点击撤销"提示条（3 秒后自动消失并真正删除）
- 或者：新增"回收站"区域，最近删除的任务可在 24 小时内恢复

**改动范围**：
- JS：`deleteItem()` 改为 `softDelete(id)`，3 秒 setTimeout 后 `hardDelete(id)`
- 新增 `undoDelete(id)` 函数
- HTML：底部新增 toast 提示条

**难度**：⭐⭐ (2/5) — toast UI + 定时器逻辑

**预计工时**：30 分钟

---

### 🟢 P2 — 可以改（锦上添花）

#### REQ-11 移动端删除按钮恢复

**问题**：CSS media query 中 `.todo-actions { display: none }` 导致手机上无法删除任务。

**需求描述**：
- 移动端改为左滑显示删除按钮（类似 iOS 原生交互）
- 或长按任务弹出操作菜单（删除/备注/标记）

**改动范围**：
- CSS：移除 display:none，改为 transform 滑出
- JS：touch 事件处理（touchstart/touchmove/touchend）

**难度**：⭐⭐⭐ (3/5) — 触摸手势处理需要仔细调参

**预计工时**：1 小时

---

#### REQ-12 金句区与待办区分离

**问题**：关键原话（金句区）和待办事项混在同一个滚动区域，干扰执行专注度。

**需求描述**：
- 金句区移至页面底部独立 Tab 或折叠面板
- 默认收起，点击"💬 会议金句"展开
- 或者做成浮动按钮，点击弹出金句卡片

**改动范围**：
- HTML/CSS：金句区改为可折叠 + 默认 collapsed
- JS：新增 toggleQuotes() 函数

**难度**：⭐ (1/5) — 复用现有折叠逻辑

**预计工时**：10 分钟

---

#### REQ-13 导出功能

**问题**：无法导出为 PDF/Excel，做周报或存档不方便。

**需求描述**：
- header 右上角增加"📥 导出"按钮
- 支持：复制全部文本 / 导出为 TXT 文件下载
- （PDF 需要引入 html2canvas/jspdf，可选）

**改动范围**：
- JS：`exportAsText()` 生成纯文本 + `downloadFile()` 触发下载
- HTML：导出按钮

**难度**：⭐ (1/5) — 纯文本导出很简单

**预计工时**：20 分钟

---

#### REQ-14 裁人计划追踪面板

**问题**："26人→18人"是重大组织变更，没有独立追踪，完成度不可量化。

**需求描述**：
- header 统计区或 timeline 区域新增"裁员进度"模块
- 显示：当前 26 人 → 目标 18 人，需裁 8 人，已裁 X 人
- 各部门裁减明细列表（可折叠）

**改动范围**：
- DATA：新增 `headcount` 对象（当前人数、目标人数、已裁列表）
- JS/HTML：新增 tracker 模块
- CSS：进度圆环或条形图样式

**难度**：⭐⭐ (2/5) — 新增数据结构 + 展示组件

**预计工时**：45 分钟

---

#### REQ-15 筛选器 bug 修复

**问题**：选"🔥紧急"时只显示紧急且未完成，无法看"所有紧急任务（含已完成）"。

**需求描述**：
- 将筛选逻辑拆分为两个维度：
  - 状态维度：全部 / 未完成 / 已完成
  - 标签维度：全部 / 紧急 / 普通
- 两个维度可独立组合（紧急+已完成 = 历史紧急任务）

**改动范围**：
- JS：`filters` 从 `{status, owner}` 改为 `{done, tag, owner}`
- HTML：筛选栏拆分重组
- render 中 `matchFilter()` 逻辑调整

**难度**：⭐⭐ (2/5) — 逻辑重构 + UI 重组

**预计工时**：40 分钟

---

#### REQ-16 标题可配置化

**问题**：标题"2026年3月22日晚宴会议 — 老王 × 凯哥 × 阿超"硬编码，无法复用。

**需求描述**：
- DATA 新增 `meta` 对象（标题、副标题、日期）
- render 时动态渲染，而非 HTML 硬编码

**改动范围**：
- DATA：新增 meta 字段
- HTML：header 区改为动态渲染
- JS：render() 中填充 meta 信息

**难度**：⭐ (1/5) — 5 分钟改完

**预计工时**：10 分钟

---

#### REQ-17 执行人筛选按钮溢出修复

**问题**："老王&凯哥"、"凯哥&阿超" 的 emoji 组合在小屏幕上会溢出。

**需求描述**：
- 小屏幕下组合执行人按钮折叠为下拉菜单
- 或改为缩写形式（"王+凯"）

**改动范围**：
- CSS：`@media (max-width:600px)` 中筛选栏改为横向滚动或下拉
- 可能需要少量 JS：下拉切换逻辑

**难度**：⭐ (1/5) — CSS overflow 处理即可

**预计工时**：15 分钟

---

#### REQ-18 云端数据同步

> **已合并到 REQ-01（多人实时协同）**，REQ-01 的实现同时解决了数据持久化和多端同步两个问题。

---

## 三、实施建议

### 第一步：解决核心问题（多人协同）
**REQ-01 多人实时协同** — 这是整个页面从"单机工具"变成"团队工具"的关键。没有这个，其他所有优化都是锦上添花。

**预计工时：3 小时**

### 第二步：快速见效（1 小时内搞定）
REQ-02 逾期标红 → REQ-06 日期补全 → REQ-13 金句折叠 → REQ-17 标题配置化 → REQ-18 筛选溢出

**合计难度：⭐⭐，约 1 小时**

### 第三步：核心体验提升（半天）
REQ-03 只看我的 → REQ-04 备注功能 → REQ-05 敏感脱敏 → REQ-10 本周视图 → REQ-11 删除撤销

**合计难度：⭐⭐，约 2.5 小时**

### 第四步：进阶功能（1-2 天）
REQ-07 新增任务 → REQ-08 进度百分比 → REQ-09 依赖关系 → REQ-12 移动端交互 → REQ-15 裁员面板

**合计难度：⭐⭐⭐，约 5-6 小时**

### 后续迭代
REQ-14 导出（可穿插）→ REQ-16 筛选 bug

---

## 四、风险提示

| 风险 | 说明 |
|------|------|
| 数据丢失 | 所有修改前应备份当前 `index.html` 和 `localStorage` 数据 |
| 敏感信息 | REQ-04 脱敏只是前端遮挡，源码中仍可见，真正安全需要后端权限控制 |
| 性能 | 41 项任务不多，但如果后续任务增长到 200+，需要虚拟滚动 |
| 兼容性 | touch 手势（REQ-11）需要在多设备实测 |
