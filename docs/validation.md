# 当前验证记录

日期：2026-10-31。

- 本地环境：Python 3.14.3、Pillow 13.0.0。
- 7 项自动检查通过：跨 2026-11-01 夏令时切换的每日日期；过期/未来数据拒绝；异常天气保留旧图片；单位检查；缺失降雨概率；PNG 格式与文件清单；拒绝覆盖其他目录。
- 实时 Redmond 数据已成功生成中文、摄氏度、五天预报，800×600 预览已视觉检查；当前天气、日期、图标和底部信息无重叠或裁切。
- 两张输出均为 L 模式、无 alpha、16 级灰度。原生排列版本 600×800；其实际摆放方向仍需 Kindle 屏幕确认。
- 作者 xh 0.16.1 配合独立的 curl 官方 CA，已在 Kindle 4 Black / 固件 4.1.2 上完成 HTTPS 下载和整文件哈希验证；访问 GitHub Pages 官方站成功。实际项目 Pages 地址要在发布后单独验证。
- 所引用的五个官方 Actions 均固定到已核对标签的完整提交 SHA，并核对了使用的输入名；GitHub Actions Ubuntu 24.04 / Python 3.14.9 上的检查、实时天气生成及 Pages 发布已成功。

实际发布地址：https://wyhangzhou.github.io/kindle-weather-dashboard/ 。Mac 已验证两张线上图片与 manifest 的 SHA-256 一致；7 项检查在云端亦通过，保活工作流手动执行成功。Kindle USB 网络当前未激活，实际项目图片下载待恢复连接。

尚待验证：定时任务持续运行、Kindle 实际项目网址下载及屏幕方向、真正的 RTC 定时休眠及唤醒、物理退出、退出后完整恢复阅读、断网恢复及电池续航。当前未运行 Dashboard 或设置自启。

最近本地天气图：

```json
{
  "schema": "kindle-weather-v1",
  "city": "Redmond",
  "timezone": "America/Los_Angeles",
  "generated_at": "2026-10-31T07:21:45.299110+00:00",
  "weather_at": "2026-10-31T07:15:00+00:00",
  "temperature_unit": "celsius",
  "kindle_rotation": "counterclockwise",
  "images": {
    "dashboard.png": {
      "sha256": "fba0072ae6521202a6abc79e6ed0fc7e4aba76f53b1f377312316303c1cedecf",
      "bytes": 18554,
      "width": 800,
      "height": 600,
      "mode": "L"
    },
    "dashboard-kindle.png": {
      "sha256": "b57d217cce9b59e18d4afa2e3d3fb593f154a9d931650bfab8eef55b86cf5e1f",
      "bytes": 22612,
      "width": 600,
      "height": 800,
      "mode": "L"
    }
  }
}
```
