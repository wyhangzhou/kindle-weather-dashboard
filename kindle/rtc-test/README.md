# 单次 30 秒 RTC 测试

这是 Kindle 4 Black / 固件 4.1.2 的有限时长测试。当前已验证前置检查，以及不休眠的 Home 事件检测、Wi-Fi 关闭和原值恢复；真正的单次定时唤醒已由内核日志确认实际休眠 30 秒、脚本耗时 33 秒，用户确认自动返回后原有书籍和实体翻页正常。它不会安装开机任务或停止原生阅读框架。

将本目录复制到 `/mnt/us/extensions/weather-wake-test/`，给三个 `.sh` 文件执行权限，重新打开 KUAL。保持 USB 接线，选择 **Wake test (30 seconds)**，准备画面出现后在 15 秒内拔线。如果仍报告充电，测试取消并返回 Home，不设置闹钟。

拔线后关闭 Wi-Fi，显示测试画面，写入 30 秒相对 RTC 闹钟，然后请求内核 `mem` 休眠。墨水屏保持原图是预期现象。恢复后脚本校验耗时和 RTC 状态，恢复原 Wi-Fi、无线开关与屏保设置，发送 Home；同时核对原生阅读进程 PID 不变。

休眠开始前可以按 Home 或选择 **Cancel wake test** 取消。休眠后若约一分钟仍未返回，短按电源键唤醒。闹钟已设置后的提前唤醒/取消会等本次最多 30 秒的闹钟到期再清理。恢复后重新接 USB 读取日志，并人工打开原有书籍、翻页；仅看到主页不代表完整验证通过。

`probe.sh --check` 只读检查接口、电量及原生 active 状态。`probe.sh --self-check` 短暂关闭 Wi-Fi，再模拟 Home 验证退出与设置恢复，不画图、不编程 RTC、不请求休眠。日志保存在 `/mnt/us/kindle-weather/tests/`，`last-wake-test.txt` 指向最近一次记录。

旧驱动的 `wakeup_enable` 写入 **0 是空操作，不能作为取消闹钟的方法**。本测试仅用 30 秒闹钟控制提前退出的等待上限；如果恢复后该属性不为 0，记录失败，不继续长周期测试。参考固定版本的 [RTC 驱动](https://github.com/fread-ink/kernel-k4-usb-otg/blob/bb242cbb9f42c1d32ccd886804f79f61803e9653/drivers/rtc/rtc-mxc_v2.c) 和 [按键驱动](https://github.com/fread-ink/kernel-k4-usb-otg/blob/bb242cbb9f42c1d32ccd886804f79f61803e9653/drivers/input/keyboard/tequila_keypad.c)。这两项源码发现仍需本机结果佐证。

`wakeUp` 在本机已经 active 时返回属性错误，因此仅在恢复时确有状态转换需要才调用；随后检查 active 状态。通过 `/proc/keypad` 发送带换行的 `send 102` 会由驱动生成 Home 按下和松开事件。这个合成事件测试不能替代真人操作和休眠中的实体键验证。

在仓库根目录运行 `.venv/bin/python kindle/rtc-test/render_screens.py` 可重建两张 600×800、L 模式、16 灰度说明图。
