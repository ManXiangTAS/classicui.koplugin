# 墨页 · ClassicUI 0.6.1

针对 Kindle 点击后退出问题的临时兼容修订。

- Kindle 暂停新增的按钮反色反馈，按钮操作、列表滚动和拖动继续可用。
- 反馈异常会记录日志并跳过效果，继续执行按钮操作；回调后的刷新也纳入前端错误处理。
- 不修改 KOReader 原生控件的反馈设置。

尚未取得报告设备的 crash.log，不能确认其闪退根因。已验证模拟器中的 Kindle 分支与重复关闭、重新创建页面流程；实机效果待确认。

完全退出 KOReader，将 `ClassicUI_0.6.1_install.zip` 中的 `einkfrontend.koplugin` 覆盖到 `koreader/plugins/`，然后重新启动。适用 KOReader v2026.07.1 / v2026.07.2；无需删除个人设置或书库。

如果仍然退出，请保留 `koreader/crash.log`，并提供设备型号、KOReader 版本和最后一次点击位置。
