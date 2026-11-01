# Kindle 中文天气屏

为 Kindle 4 生成清晰的中文灰度天气图。默认 Redmond, Washington、摄氏度、五天天气、美国太平洋时区。天气图由 GitHub Actions 更新并部署到 GitHub Pages，家中无需常开服务器。

## 生成内容

| 文件 | 用途 |
| --- | --- |
| `dashboard.png` | 800×600 横向天气图，适合浏览器预览 |
| `dashboard-kindle.png` | 同一画面旋转为原生 600×800 像素排列，供 Kindle 实机方向测试 |
| `manifest.json` | 数据时间、生成时间、图片尺寸及 SHA-256 |
| `device-manifest.txt` | 旧 Kindle 可严格解析的时间、有效期、格式及传输校验信息 |
| `weather.json` | 已验证并转换为中文界面所需的数据 |
| `index.html` | 自动刷新的浏览器预览页 |

图片为无透明通道的 `L` 模式 PNG，最多 16 个灰度。当前天气包括温度、体感、天气状况、湿度、风速和当天降雨概率；下方显示未来五天的高低温和降雨概率。时间按 `America/Los_Angeles` 显示。

## 本地运行

需要 Python 3.11 或更新版本；本项目当前在 Python 3.14 上验证。

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python generate.py
```

输出在 `public/`，可直接打开 `public/dashboard.png` 查看。生成器只替换带有本项目输出标记的目录，拒绝覆盖其他已有文件夹。

API 请求失败、数据超过 90 分钟、单位异常或预报不完整时，生成器返回失败，不生成替代天气。GitHub 工作流因此不执行发布，线上继续保留上一次成功的图片；屏幕上的数据日期可用于判断是否已陈旧。缺失的降雨概率显示 `—`。

## GitHub Pages 部署

1. 将本目录作为独立仓库上传到 GitHub，默认分支为 `main`。
2. 在 Settings → Pages 中将 Source 设为 **GitHub Actions**。
3. 在 Actions 中执行 **Update weather**。成功后使用该仓库的 Pages 地址。

当前已发布的天气预览：[打开天气页](https://wyhangzhou.github.io/kindle-weather-dashboard/)。

Kindle 图片地址为：

```text
https://wyhangzhou.github.io/kindle-weather-dashboard/dashboard-kindle.png
```

Mac 已核对线上两张 PNG 的尺寸、灰度格式及 SHA-256；Kindle 也已从本项目 Pages 实际下载 manifest 和原生排列 PNG，HTTPS 返回 200，文件 SHA-256 与线上清单完全一致。

首次成功部署：[Update weather](https://github.com/wyhangzhou/kindle-weather-dashboard/actions/runs/41245412215)（第 2 次尝试；首次因 Pages 尚未启用而失败）。每月保活也已通过一次手动执行验证。

云端默认在每小时第 11、26、41、56 分钟更新，约每 15 分钟一次；设备仍约每 30 分钟取图，为云端排队留出余量。避开整点是为了降低排队概率；GitHub 的定时任务可能延迟或被丢弃，并非精确定时服务。公开仓库没有活动达到 60 天时，定时工作流可能停用，因此另有每月一次的小型保活提交。保活只更新 `.github/keepalive`，不把每张天气图提交到 Git 历史。

如果保活失败或定时任务被停用，在 Actions 中重新启用工作流并手动执行一次，随后检查失败记录。平台的调度、仓库权限和可用性仍需实际长期验证。

2026-10-31 晚上的实测发现：工作流 active 且 cron 正确，仍出现数小时无新定时运行，设备因此在首次下载就拒绝过期天气并退出，未休眠。随后手动刷新 [41278223040](https://github.com/wyhangzhou/kindle-weather-dashboard/actions/runs/41278223040) 成功，Kindle 新图下载和读回哈希一致。自动供图可靠性尚未通过。已准备 [Cloudflare 独立定时备用方案](cloudflare/README.md)，本地检查通过，尚未接入账号或部署。

公开仓库可以使用 GitHub Free 的 Pages；当前工作流使用标准 Ubuntu 托管运行器，每次最长 5 分钟，Pages 构建产物保留 1 天。当前已验证一次云端天气构建及发布、一次保活执行；长期定时运行仍需观察。

## 修改城市、单位和间隔

修改 `config.toml` 中的 `city`、`region`、`latitude`、`longitude` 和 `timezone`。坐标可以通过 [Open-Meteo 地理编码接口](https://open-meteo.com/en/docs/geocoding-api) 查询；城市与时区应一起调整。

- `temperature_unit`：`celsius` 或 `fahrenheit`；天气 API 内部始终取摄氏度，显示时转换。
- `forecast_days`：3 至 5。
- `kindle_rotation`：`counterclockwise` 或 `clockwise`，应以 Kindle 实际摆放和按键位置为准。
- 云端刷新频率：修改 `.github/workflows/weather.yml` 的 cron。Kindle 端下载间隔需要在设备运行器完成后独立设置。

当前天气时间使用真正的 UTC 时间戳转换本地时区。Open-Meteo 的每日数据采用响应中固定的 UTC 偏移定义日期，代码按该规则解码；跨夏令时测试覆盖 2026-11-01，避免预报日重复。

## Kindle 端进度

已经在 Kindle 4 Black / 固件 4.1.2 上验证 KUAL、USB SSH、原生阅读，以及带独立 CA 的 xh HTTPS 下载。原版 KUAL 的签名算法需要兼容处理，该设备已使用程序内容不变的兼容签名副本。

云端图片与 Kindle 实际下载已验证。一次性预览的中文显示、方向、Home 返回和原有书籍翻页均已由用户确认正常。`kindle/rtc-test/` 提供单次 30 秒唤醒测试，前置检查及不休眠恢复自检通过，真实 RTC 测试已由内核日志验证实际休眠 30 秒并自动恢复，用户确认随后原有书籍和翻页正常；长周期和连续刷新仍待验证。`kindle/preview/` 提供 KUAL 一次性预览入口，安装后选择 **Weather preview**，用于核对屏幕方向和中文显示，具体步骤见该目录 README。设备的定时休眠、唤醒、物理退出和完整恢复阅读仍需逐项实测。尚未设置 Dashboard 开机自动运行。独立 CA 和下载工具放在用户目录，保留系统组件。实际续航不能由接口存在或电量百分比推算。

## 启动天气模式

KUAL 中的 **Weather** 子菜单提供持续运行、一次完整 30 分钟试运行和 Stop / Read。源码与构建说明见 [Kindle 运行器](kindle/dashboard/README.md)。短周期下载/显示/休眠/再下载、真人 Home 退出，以及原定 120 秒的休眠在 7 秒提前唤醒后恢复原闹钟均已实测通过；实际 1800 秒定时唤醒已通过；首轮完整试运行发现启动器活动期间的超时重启，已修正启动器退出方式，整轮复测和长期续航仍待完成。没有设置开机自动运行。

## 数据和字体

天气数据来自 [Open-Meteo](https://open-meteo.com/)，按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 使用并在图片、预览页中署名。本项目为个人家庭信息屏，按其 [免费非商业 API 条款](https://open-meteo.com/en/terms) 使用。

中文字体为 Google Noto Sans SC，原文件和校验信息在 `assets/fonts/`，许可证为同目录 `OFL.txt`。天气图标由本项目代码绘制。

参考：[天气 API 参数](https://open-meteo.com/en/docs)、[Pages 工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)、[定时工作流规则](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。
