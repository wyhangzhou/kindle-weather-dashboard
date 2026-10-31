# 当前验证记录

日期：2026-10-31。

- 本地环境：Python 3.14.3、Pillow 13.0.0。
- 7 项自动检查通过：跨 2026-11-01 夏令时切换的每日日期；过期/未来数据拒绝；异常天气保留旧图片；单位检查；缺失降雨概率；PNG 格式与文件清单；拒绝覆盖其他目录。
- 实时 Redmond 数据已成功生成中文、摄氏度、五天预报，800×600 预览已视觉检查；当前天气、日期、图标和底部信息无重叠或裁切。
- 两张输出均为 L 模式、无 alpha、16 级灰度。原生排列版本 600×800；用户照片确认实体按键在左时横向显示完整。
- 作者 xh 0.16.1 配合独立的 curl 官方 CA，已在 Kindle 4 Black / 固件 4.1.2 上完成 HTTPS 下载和整文件哈希验证；访问 GitHub Pages 官方站成功。实际项目 Pages 下载也已由本机验证。
- 所引用的五个官方 Actions 均固定到已核对标签的完整提交 SHA，并核对了使用的输入名；GitHub Actions Ubuntu 24.04 / Python 3.14.9 上的检查、实时天气生成及 Pages 发布已成功。

实际发布地址：https://wyhangzhou.github.io/kindle-weather-dashboard/ 。Mac 已验证两张线上图片与 manifest 的 SHA-256 一致；7 项检查在云端亦通过，保活工作流手动执行成功。恢复 USB 后，Kindle 已实际下载本项目 Pages manifest 和 PNG，均返回 HTTP/2 200，SHA-256 与清单一致；联网后的开发者证书库仍匹配。

尚待验证：定时任务持续运行、自动循环的定时休眠及唤醒、物理退出与完整恢复阅读、断网恢复及电池续航。一次性天气预览和其后的 Home/原生阅读已由用户确认正常；尚未运行自动循环或设置自启。

最初本地输出示例（历史记录，并非当前线上数据）：

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


已安装 `kindle/preview/` 一次性 KUAL 预览入口，XML/JSON 和 shell 语法通过，设备 `--check` 通过，复制读回哈希一致。`exitmenu: false` 的支持已从本版本 KUAL 的 parse.awk 核对，保持 KUAL 活动以便 Home 返回。用户随后提供了真实 e-ink 照片：实体按键在左的横向中文天气图显示完整，当前温度、日期和五天天气均可见。屏幕方向与显示已通过。用户随后回复“正常”，确认按 Home 返回、原有书籍显示及实体键翻页正常。

已准备 `kindle/rtc-test/` 单次 30 秒测试。设备只读检查通过；不休眠的自检已通过，日志确认合成 Home 事件触发退出，Wi-Fi、屏保与 active 状态恢复，阅读进程 PID 不变，RTC 请求保持 0。该合成事件结果不能代替真人按键验证。随后用户执行有限时长 RTC 测试并报告自动回到 Home；设备日志显示脚本经过 33 秒，内核记录实际休眠 30 秒，RTC 归零、Wi-Fi/屏保原值恢复，Wi-Fi 重新连接，阅读进程 PID 不变。用户随后确认此次休眠后的原有书籍显示和实体翻页正常。在不休眠的清理实验中复现了旧 shell 等待被 TERM 中断后遗留输入子进程的问题；保留子进程 PID 至清理完成，并增加停止标记后，收尾和 Home 自检均通过，无遗留监听进程。仍不能据单次 RTC 通过宣称连续运行或持续按键退出可靠。


`kindle/weather-test/` 两次刷新入口已准备，尚未真实触发两次下载/显示/休眠组合。前置检查及无休眠的 Home、显式 Stop 检查通过，原设置与 CVM PID 恢复且无遗留输入监听。13 项本机清单/图片检查通过：正确文件接受，12 种校验和、长度、格式、字段、有效期及整数异常拒绝。真实 Pages 的新清单与 PNG 已由设备下载，Mac 读回 SHA-256 也一致；404 下载失败保留旧缓存并释放锁。受控的网络等待进程取消测试确认子进程被回收、旧缓存保留、锁释放。这些结果不能代替实际断网后的持续重试、唤醒后的实体 Home 退出、长周期立即退出及续航验证。

云端增加 `device-manifest.txt` 后的构建、7 项检查与部署已成功：[Update weather 41249993220](https://github.com/wyhangzhou/kindle-weather-dashboard/actions/runs/41249993220)。
