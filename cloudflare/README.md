# Cloudflare 云端备用定时器

GitHub 原生定时触发在本项目的观察中出现过数小时空档。2026-10-31 晚上的设备复测因此在第一次下载即因天气过期退出，尚未休眠。手动触发同一流程后，生成、发布和 Kindle 下载恢复成功；这不能证明自动调度已经恢复可靠。

此 Worker 给现有 GitHub 流程增加独立的时钟。它每 15 分钟检查 Pages：生成时间超过 20 分钟，或天气有效期不足 45 分钟，以及页面无法读取时，尝试触发 `weather.yml` 的 `workflow_dispatch`。图片仍由原来的 Python 生成并发布到原 Pages；Kindle 配置不需要更改。GitHub 原生定时可保留。

2026-11-02 已按用户选择部署到自己的 Cloudflare 账号，并配置正式环境加密 Secret 和 Cron。自动事件的实际验证结果见 [验证记录](../docs/validation.md)。它降低对单个定时器的依赖，GitHub 运行器、Pages 或天气 API 故障仍可能影响更新。

## 账号、权限和费用

- 使用用户自己的 Cloudflare **Workers Free** 账号。每 15 分钟一天 96 次检查，最多 96 次 GitHub 触发请求；无需付费计划、KV、数据库、域名或家庭服务器。
- 建立一个新的 GitHub **fine-grained personal access token**：Resource owner 为 `wyhangzhou`，Repository access 只选 `kindle-weather-dashboard`，Repository permissions 只加 **Actions: Read and write**（Metadata read 为系统必需）。不添加 Contents 写权限。这种权限可管理该仓库的 Actions，不能限制到单一工作流；本程序只调用固定的天气工作流。
- 令牌设置有限有效期，并记下到期日以便更换。本项目当前专用令牌到期日为 **2027-11-02**，到期前需更换。不要把 Mac 当前的通用 GitHub 登录凭据复制给 Worker。
- 令牌只保存为用户 Cloudflare Worker 的加密 Secret **`GITHUB_WEATHER_TOKEN`**，不放在代码、日志、聊天或 Kindle 上。撤销 GitHub 令牌或删除 Cron 即可停止该备用路径。

## 运行配置

源文件为 `worker.mjs`，Wrangler 配置为 `wrangler.toml`，Worker 名称为 `kindle-weather-scheduler`。Cron 为 UTC `4,19,34,49 * * * *`，不受夏令时重复或缺失影响。没有公开 HTTP 触发入口，HTTP 请求返回 404；配置关闭 workers.dev 和预览 URL。正式环境只需要一个加密 Secret：`GITHUB_WEATHER_TOKEN`；不把它添加到 Previews。执行日志保存在用户自己的 Cloudflare 账号，程序只记录更新结果或 HTTP 错误状态，不记录令牌。

两个网络请求均使用 `redirect: "manual"`：Pages 的 3xx 视为不可读取，GitHub 的 3xx 视为触发失败，不访问 `Location`。Workers 不支持标准 Fetch 的 `redirect: "error"`，会在发出请求前抛出 TypeError；此差异由首次真实 Cron 发现，已修正并增加回归检查。本地模拟的 7 项检查不能替代实际平台验证。

初次安装可通过 Cloudflare 控制台或 Wrangler 上传源码，先保持 Cron 为空，添加上述 Secret，再启用定时。Cron 变更最多可能需要 15 分钟传播。部署命令成功或配置读回一致只能证明配置存在，不能替代真实事件验证。

修改 Worker 源码或 Cron 配置后，需重新部署到 Cloudflare。GitHub 天气工作流会执行其回归检查，Cloudflare 部署仍由维护者单独完成。

本地验证（使用 Node 24；无第三方库、无真实令牌、无网络请求）：

```sh
node --test cloudflare/test-worker.mjs
```

接入后观察真实 Cron 事件，覆盖旧图触发和新图跳过两条路径；可临时增加短间隔验证触发器，完成后删除并读回正式配置。日志中的 `dispatch-accepted` 只表示 GitHub 接受请求，不代表图已发布；必须继续核对工作流结果和 `manifest.json` 的生成/天气时间。新鲜数据会记录 `already-fresh` 并跳过额外构建。

## 使用与排查

日常不需要打开 Cloudflare 页面，Mac 关机后云端仍会运行。Kindle 继续按自身约 30 分钟的周期取图，所以云端发布后，设备要等下一次成功联网才会显示。

图片长时间没更新时，依次检查：

1. Cloudflare → Workers & Pages → `kindle-weather-scheduler` → Observability，确认有近期 Cron 事件。`already-fresh` 是正常跳过，`dispatch-accepted` 表示已请求 GitHub 更新。
2. GitHub → 天气仓库 → Actions → Update weather，检查随后出现的 `workflow_dispatch` 运行是否成功。
3. 访问 Pages 的 `manifest.json`，核对 `generated_at` 和 `weather_at`，再判断设备是否下载了新图。

GitHub HTTP 401 通常表示令牌失效；403 还需检查仓库范围、Actions 权限或限流。更换令牌时按相同单仓库权限创建，再更新 Cloudflare 正式环境的同名 Secret，确认一次自动发布成功后撤销旧令牌。API/构建失败会保留上一张图片。

停止备用路径时，在 Cloudflare Worker Settings → Trigger events 删除 Cron，或在 GitHub 撤销专用令牌；前者不影响 GitHub 原有定时任务。清空触发器时应显式保留 `crons = []`，避免把“未配置该项”误当成“删除已有触发器”。

## 官方依据

- [GitHub 定时触发会延迟或丢弃任务](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
- [workflow dispatch 及 Actions 写权限](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
- [Cloudflare Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/)
- [Workers 免费额度与 CPU 限制](https://developers.cloudflare.com/workers/platform/pricing/)
- [加密 Secret](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Workers Request 的重定向模式](https://developers.cloudflare.com/workers/runtime-apis/request/)
