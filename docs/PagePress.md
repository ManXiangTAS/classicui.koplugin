# Voyage PagePress（0.4.0-test.2）

入口：设置 → 触控与按键 → 翻页键（0.4.0-test.3 起统一中文名称，搜索 PagePress 仍可定位）。仅 `Device.model == KindleVoyage` 时安装服务，其他设备不访问驱动。

支持：翻页开关、按压力度、震动开关、四档反馈强度，以及调用 KOReader 原生“反转翻页方向”。左右两侧硬件产生相同方向键码，因此不提供左右独立设置。100 / 150 / 200 是墨页预设，并不宣称等于 Kindle 原生的轻中重三档；150 是所核对驱动中的默认压力常量。数值越小越容易触发。

## 接口依据

核对 Amazon GPL 内核源码镜像 [linux-3.0.35-lab126](https://github.com/katadelos/linux-3.0.35-lab126)，以下文件均位于 master：

- `include/linux/lab126_keypad.h`：`/dev/keypad`、magic B、GET_LOCK。
- `include/linux/lab126_fsr.h`、`drivers/input/keyboard/fsr_keypad.c`（blob `ec3068855dd457984f7d088f2a8d2ae619091a63`）：32 位整数 GET/SET_PRESSURE、PREV_ENABLE、NEXT_ENABLE。驱动 SET_PRESSURE 自动使用一半的释放阈值。GET_PRESSURE 只能返回按下阈值，因此恢复原值遵循同一原生 SET_PRESSURE 语义，不能保证恢复由第三方直接写寄存器产生的任意释放阈值。
- `include/linux/lab126_haptic.h`、`drivers/input/keyboard/drv26xx_haptics.c`（blob `77a5bbcc75f0d3c3159a39e0e58dc0ae612682b8`）：`/dev/haptic`、magic C、GET/SET_LOCK；lock=1 阻止播放。gain 取值 0..3，0 是最弱档，不是关闭。
- 该版本 GET_GAIN 返回 curr_gain 缓存，而 SET_GAIN ioctl 不更新该缓存。因此通过 `/sys/devices/system/drv26xx_haptics/drv26xx_haptics0/gain_setting` 设置 gain，并从同目录 `id` 属性返回的实际控制寄存器低两位核对。格式不匹配时禁用该项，不回退到猜测的属性名。
- KOReader 固定基线 `9192014d8bd82a91dc1012473be0f238dedfdb54` 的 `frontend/device/kindle/device.lua` 和 `physical_buttons.lua`：Voyage 104/109 映射 LPgBack/LPgFwd，原生反转用 SwapPageTurnButtons 事件。没有启用 xset 自动重复、没有编辑系统固件或 appreg.db。

## 保存与生命周期

硬件覆盖保存在 KOReader 全局 `eink_pagepress` 键中。初次安装不写设备，不假设用户原值。每项写入后读回；保存后重新打开配置文件核对。失败尝试回滚并报告原因。原始上一页/下一页独立开关状态、震动关闭状态、非预设压力都按进入时值保存。

书库和阅读器共享服务。最后一个实例停用、正常退出或休眠时尝试恢复原值；唤醒或重新进入时应用已保存的覆盖。如果其他软件已经改变该项，不覆盖其更改。硬件异常、进程强制终止或断电不能保证退出恢复；在 Kindle 原生设置中仍可重新调整。

“沿用 Kindle 设置”清除此项覆盖并恢复本次进入时读取的值。反转方向沿用 KOReader 自身持久设置，不属于硬件覆盖。

## 验证边界

桌面以实际 ABI 适配器和模拟驱动检查：压力与释放规则、两键部分写失败回滚、震动关闭与 gain=0、设备锁定、读回拒绝、配置写失败及静默失败、损坏配置、重启、休眠、外部更改、多实例和设置搜索。三种分辨率渲染原生设置页并核对文字与数值垂直中心。

**尚未连接 Voyage 5.13.6 实机**。接口是否在该固件保持一致、原生服务是否覆盖配置、压力手感、震动强度和恢复行为均需真机验证。功能作为测试版发布，不把桌面模拟通过视为硬件验证。
