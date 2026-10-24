# 回归测试

测试需要官方 KOReader Linux 模拟器运行目录（包含 luajit 与 SDL 库），并将其 `plugins/einkfrontend.koplugin` 链接到本仓库插件目录。测试使用隔离设置和原创示例书籍，不修改真实书库。

```sh
python3 tests/run_regression.py /path/to/koreader
```

可用 `--suite core` 等参数运行指定组。覆盖价格与元数据、布局迁移、点击反馈与滚动、离线启动、中英输入、原生控件、主页、屏保和设置菜单。

浏览器测试需要 Node.js、Playwright 和 Chromium，设置 `EINK_CHROMIUM` 为浏览器路径：

```sh
npm install --prefix tests
EINK_CHROMIUM=/path/to/chromium python3 tests/run_web.py /path/to/koreader upload
EINK_CHROMIUM=/path/to/chromium python3 tests/run_web.py /path/to/koreader home_editor
```

日志与画面输出到忽略的 `test-results/`，不进入源码与安装包。真实 Kindle 的显示与硬件操作仍需实机检查。

发布流程默认只生成草稿。维护者确认后，可手动运行构建并勾选发布，或使用与当前版本完全一致的提交标题 `Release ClassicUI <版本号>`；普通推送不会公开新版本。发布策略检查：`python3 tests/test_release_policy.py`。
