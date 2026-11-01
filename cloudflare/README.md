# 云端定时备用方案（已准备，尚未部署）

GitHub 原生定时触发在本项目的观察中出现过数小时空档。2026-10-31 晚上的设备复测因此在第一次下载即因天气过期退出，尚未休眠。手动触发同一流程后，生成、发布和 Kindle 下载恢复成功；这不能证明自动调度已经恢复可靠。

此 Worker 给现有 GitHub 流程增加独立的时钟。它每 15 分钟检查 Pages：生成时间超过 20 分钟，或天气有效期不足 45 分钟，以及页面无法读取时，尝试触发 `weather.yml` 的 `workflow_dispatch`。图片仍由原来的 Python 生成并发布到原 Pages；Kindle 配置不需要更改。GitHub 原生定时可保留。

当前状态：仅本地准备和模拟检查。没有创建 Cloudflare 账号、上传凭据、部署 Worker 或配置实际定时。用户接入账号后，还需验证真实 Cron 事件、GitHub 运行、Pages 新时间及 Kindle 下载，才能认为该备用路径可用。它降低对单个定时器的依赖，不能保证 GitHub 运行器或天气 API 始终可用。

## 账号、权限和费用

- 使用用户自己的 Cloudflare **Workers Free** 账号。每 15 分钟一天 96 次检查，最多 96 次 GitHub 触发请求；无需付费计划、KV、数据库、域名或家庭服务器。
- 建立一个新的 GitHub **fine-grained personal access token**：Resource owner 为 `wyhangzhou`，Repository access 只选 `kindle-weather-dashboard`，Repository permissions 只加 **Actions: Read and write**（Metadata read 为系统必需）。不添加 Contents 写权限。这种权限可管理该仓库的 Actions，不能限制到单一工作流；本程序只调用固定的天气工作流。
- 令牌设置有限有效期，并记下到期日以便更换。不要把 Mac 当前的通用 GitHub 登录凭据复制给 Worker。
- 令牌只保存为用户 Cloudflare Worker 的加密 Secret **`GITHUB_WEATHER_TOKEN`**，不放在代码、日志、聊天或 Kindle 上。撤销 GitHub 令牌或删除 Cron 即可停止该备用路径。

## 准备好的配置

源文件为 `worker.mjs`，Wrangler 配置为 `wrangler.toml`。Cron 为 UTC `4,19,34,49 * * * *`，不受夏令时重复或缺失影响。没有公开 HTTP 触发入口，HTTP 请求返回 404；配置关闭 workers.dev 和预览 URL。

可以通过 Cloudflare 控制台创建 Worker 并粘贴源码、添加上述 Secret 和 Cron；或使用项目范围的 Wrangler 执行相同配置。首次部署前先设置 Secret，再启用 Cron。Cloudflare 的 Cron 变更可能需要传播时间。

本地验证（使用 Node 24；无第三方库、无真实令牌、无网络请求）：

```sh
node --test cloudflare/test-worker.mjs
```

接入后，先执行一次真实测试事件，再观察至少两次自然 Cron 事件。日志中的 `dispatch-accepted` 只表示 GitHub 接受请求，不代表图已发布；必须继续核对工作流结果和 `manifest.json` 的生成/天气时间。新鲜数据会记录 `already-fresh` 并跳过额外构建。GitHub 401 通常需要更换或修正令牌权限，API/构建失败会保留上一张图片。

## 官方依据

- [GitHub 定时触发会延迟或丢弃任务](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
- [workflow dispatch 及 Actions 写权限](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
- [Cloudflare Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/)
- [Workers 免费额度与 CPU 限制](https://developers.cloudflare.com/workers/platform/pricing/)
- [加密 Secret](https://developers.cloudflare.com/workers/configuration/secrets/)
