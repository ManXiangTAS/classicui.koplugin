# 回归测试

测试需要官方 KOReader Linux 模拟器运行目录（包含 luajit 与 SDL 库），并将其 `plugins/einkfrontend.koplugin` 链接到本仓库插件目录。测试使用隔离设置和原创示例书籍，不修改真实书库。

```sh
python3 tests/run_regression.py /path/to/koreader
```

可用 `--suite core` 等参数运行指定组。覆盖价格与元数据、布局迁移、点击反馈与滚动、离线启动、中英输入、原生控件、主页、屏保、设置菜单和自动前光。

`--suite maintenance` 使用隔离书库和复制文件验证删除确认、取消、失败、已打开保护，以及残留扫描、预览后恢复、同名多格式、中央 / 哈希元数据、封面数据库、路径链接、存储变化和重试。原始示例书与历史统计保持不变。

自动前光的曲线、记忆、手动优先、硬件与存储故障、休眠等策略检查可用 LuaJIT 独立执行：`luajit tests/test_light_policy.lua`。`--suite autolight` 使用模拟传感器与真实 KOReader 设置、Powerd 和界面，验证入口、校准预览与取消、读写设置、休眠和阅读返回；这不替代真实光感与功耗测试。

浏览器测试需要 Node.js、Playwright 和 Chromium，设置 `EINK_CHROMIUM` 为浏览器路径：

```sh
npm install --prefix tests
EINK_CHROMIUM=/path/to/chromium python3 tests/run_web.py /path/to/koreader upload
EINK_CHROMIUM=/path/to/chromium python3 tests/run_web.py /path/to/koreader home_editor
```

日志与画面输出到忽略的 `test-results/`，不进入源码与安装包。真实 Kindle 的显示与硬件操作仍需实机检查。

发布流程默认只生成草稿。维护者确认后，可手动运行构建并勾选发布，或使用与当前版本完全一致的提交标题 `Release ClassicUI <版本号>`；普通推送不会公开新版本。发布策略检查：`python3 tests/test_release_policy.py`。

## 本机离线逻辑检查（0.7.4）

需要 Python、Node.js，以及安装在 tests/node_modules 的 Fengari：

    npm install --prefix tests
    python tests/run_local_checks.py

也可将 FENGARI_ROOT 设置为已有 Fengari 的 src 目录，避免重复下载依赖。运行不会请求 GitHub、修改真实书库或调用设备硬件。发布测试使用内存 HTTP 替身，网页检查使用 Node VM 和简化 DOM/HTTP 替身；Lua 检查使用 Fengari Lua 5.3。

这组检查覆盖发布策略、安装包完整性/摘要/重复构建、原前光策略、故障注入与网页脚本逻辑。结果位于 test-results/local/combined-summary.json。它不能代替上文所述 LuaJIT、SDL/crengine/MuPDF 模拟器、Playwright 浏览器联调及 Kindle 真机测试。

新增 test_light_upgrade.lua 验证可调曲线、环境目标变化后的手动恢复、唤醒立即/1 秒复查、简化后的设置导航与输入校验，以及数字位于滑块正上方的绘制坐标。此绘制检查使用替身，不验证真实字体栅格。

`test_folder_collections.lua` 验证文件夹收藏预览、嵌套命名、合并与重复导入、目录/书籍变化、备份失败和保存回滚、书库目录外的收藏成员，以及阅读顶部 Aa 与底部/中央触控入口。它使用模拟文件系统与 KOReader 接口，由本机检查自动运行；可单独执行 `node tests/run_portable_audit.cjs . library`。原生 `interaction` 组另有实际触摸事件与 Aa 展开检查；未在 Windows 上执行原生组。

`test_device_feedback.lua` 覆盖29.5字号下更换字体、字重、对比度和应用主题的保存，以及导入预览中的新增/补入/已导入、空目录、各状态按钮和桌面/Voyage尺寸/横屏下的固定操作区。由本机检查自动运行；可单独执行 `node tests/run_portable_audit.cjs . feedback`。使用模拟绘制后端记录实际页面布局，`python tests/render_feedback_previews.py` 可用 Pillow 和本机字体生成预览（其他系统使用 `--font` 和 `--bold-font` 指定字体）。预览不替代原生字体渲染及真机验证。

`test_home_capacity.lua` 覆盖半行部件取消后重新配对的容量恢复：实际调用Fit、Layout和Editor模块，替换设备、存储与预览绘制。检查纯隐藏允许执行、溢出草稿仍不能显式保存、连续隐藏后可保存、旧式自动保存页保留关闭选择、手机共用草稿替换及版本冲突、混合新增/扩宽/重排/偏好编辑不绕过容量限制，以及多种组合和原转述操作的模拟。可单独执行 `node tests/run_portable_audit.cjs . home_capacity`；本机总检查自动包含此组，不代表真实手机HTTP或Kindle硬件通过。
