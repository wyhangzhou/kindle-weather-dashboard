# 一次性屏幕预览

将本目录复制到 Kindle 的 `/mnt/us/extensions/weather-preview/`，重新打开 KUAL 后选择 **Weather preview**。入口使用已经下载并校验的 `/mnt/us/kindle-weather/checks/project-dashboard.png`，约 2 秒后显示一次。

当前图片按 600×800 原生像素排列保存，画面内容为横向 800×600；先将设备横放，使实体按键位于左边，再核对方向。如果需要另一种摆放方向，调整云端 `config.toml` 的 `kindle_rotation` 后重新生成并下载。

预览保留 KUAL 和原生阅读服务运行，按 **Home** 返回原生主界面。这是一次性显示检查，图片不会由此入口自动更新；原生屏保和休眠策略保持正常运行。

自动刷新、Wi-Fi 定时开关、RTC 唤醒和完整退出恢复将在后续运行器中分别测试。尚未设置任何开机自动运行。

检查命令 `preview.sh --check` 仅检查图片和 eips 存在，不改屏幕。显示错误记录在 `/tmp/kindle-weather-preview.log`。
