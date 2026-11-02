# Kindle 4 实体屏幕刷新同步

2026-11-01 用户照片显示启动提示、天气图和条纹叠在一起。此前的 framebuffer 截图检查只证明内存中的像素正确，不能证明实体墨水屏已经完成刷新。

设备追踪确认：`eips -f -g` 请求的是 full update，但 ioctl 很快返回；驱动随后仍可能处理屏幕更新。旧流程绘图后立即进入 `mem`，缺少实体刷新完成的屏障。因而仅凭 `eips` 退出成功或执行文件系统 `sync`，不能作为允许休眠的依据。

现有 K4 驱动提供 `/proc/eink_fb/update_display` 命令 **21**，对应 `FBIO_WAITFORVSYNC`。它进入 `einkfb_update_display_sync()`，再等待 EPDC 最后一条更新标记完成。这里只使用显示等待命令，不更改显示旋转、波形文件、电源策略、系统时钟或 RTC 寄存器。

正式显示流程：

1. 关闭 Wi-Fi，等待原生状态栏事件完成。
2. 等待此前屏幕更新结束。
3. 全屏清白，再等待清屏完成。
4. 绘制完整天气图，再等待实体更新完成。
5. 进入 `mem` 前再次等待所有待处理更新结束。

启动提示也使用相同的清屏和等待流程。每次更新会有短暂全屏闪烁。显示或等待失败时返回错误并走原有恢复流程，不继续提交后续绘图或休眠。

验证：12 项本地及云端检查通过，新增检查覆盖清屏/绘图/等待的顺序，以及等待失败时停止后续绘图。保持 USB 接线的实机清屏与等待测试后，用户明确确认“已清晰，没有叠影”。随后从 Mac 启动已安装的正常模式，用户按提示拔线、等待天气图稳定约 10 秒后，再次明确确认“已拔线，画面清晰稳定”。这次验证包含实体屏幕观察；新版下一次 30 分钟自动唤醒后的长期表现仍需自然运行观察。

固定上游源码：

- [命令 21 与 WAITFORVSYNC 定义](https://github.com/fread-ink/kernel-k4-usb-otg/blob/bb242cbb9f42c1d32ccd886804f79f61803e9653/include/linux/einkfb.h)
- [proc 命令转发](https://github.com/fread-ink/kernel-k4-usb-otg/blob/bb242cbb9f42c1d32ccd886804f79f61803e9653/drivers/video/eink/hal/einkfb_hal_proc.c)
- [显示同步与异步更新入口](https://github.com/fread-ink/kernel-k4-usb-otg/blob/bb242cbb9f42c1d32ccd886804f79f61803e9653/drivers/video/eink/hal/einkfb_hal_util.c)
- [EPDC 更新标记等待](https://github.com/fread-ink/kernel-k4-usb-otg/blob/bb242cbb9f42c1d32ccd886804f79f61803e9653/drivers/video/eink/fslepdc/fslepdc_hal.c)
