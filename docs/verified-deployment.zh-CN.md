# 实机部署验证记录

本文档记录本修复版在真实 Cloudflare 账号上完成的一次端到端部署与验收，用来说明「修补不只是改文档，部署链路确实能跑通」。全文**不包含任何 Token、订阅地址、节点信息或私有数据库 ID**；示例域名一律写作 `<自定义域名>`。

## 验证环境

| 项 | 版本 / 环境 |
| --- | --- |
| 操作系统 | Windows 11（Windows PowerShell 5.1） |
| Node.js | 22.22.2 |
| pnpm | 11.7.0（Corepack 启用） |
| Wrangler | 4.159.0 |
| Cloudflare 套餐 | Workers Free |
| 组件 | Workers Static Assets + Worker API + D1 + Worker Secrets |

Node / Git / Corepack 均不在系统 PATH 中（使用 IDE 自带的运行时），由 `scripts/install-fixed.ps1` 自动探测后注入当前会话 PATH。

## 部署结果

| 项 | 结果 |
| --- | --- |
| Worker | 上传成功，启动 9 ms，当前版本承载 100% 流量 |
| 静态资源 | 64 个文件，540.71 KiB（gzip 118.85 KiB） |
| D1 | 3 个 migration 全部应用；复查显示 `No migrations to apply!` |
| Worker Secrets | `SUB_STORE_ADMIN_TOKEN`、`SUB_STORE_PUBLIC_DOWNLOAD_TOKEN` 均已写入并可枚举 |
| 管理前端 | 通过自定义域名返回 HTTP 200，页面版本 1.1.0 |

## 验收矩阵

| 检查 | 结果 | 说明 |
| --- | --- | --- |
| `GET /` | 200 | 需浏览器 User-Agent；返回管理前端 HTML |
| `GET /api/env` + admin token | 200 | `app: Sub-Store Cloudflare`、`backend: Cloudflare`、`version: 1.1.0` |
| `GET /api/templates` + admin token | 200 | 内置模板可用 |
| `GET /api/sources` + admin token | 200 | 空部署返回空数组 |
| `GET /api/collections` + admin token | 200 | migration 预置 `daily`（模板 `acl4ssr-mihomo`） |
| `GET /api/env` + download token | 401 | `Admin token is invalid`——鉴权分离正确 |
| `GET /api/env` 不带 token | 401 | 管理接口默认拒绝 |
| 订阅下载 + 客户端 UA | 到达应用 | `clash-verge` / `Mihomo` / `Shadowrocket` / `curl` / 浏览器 UA 均未被 WAF 拦截 |

## 过程中修掉的四个 Windows / D1 兼容问题

详细的根因、修补清单与设计决策见 [PATCH_NOTES.md](../PATCH_NOTES.md)，这里只列现象：

1. `scripts/install-fixed.ps1` 首版报「无法将 git 项识别为 cmdlet」——IDE 自带 Git / Node 不在用户 PATH，改为自动探测并注入。
2. 安装器报 `pnpm is required.`——上游用 `spawnSync("pnpm")`，而 Windows 上 Corepack 只提供 `.CMD` / `.ps1` shim；改为由 `node.exe` 直调 Corepack 的 `pnpm.js`。
3. `wrangler types --check` 报 `Types ... are out of date`，以及 `build:frontend` 报 `'VITE_API_URL' 不是内部或外部命令`——前者重新生成类型声明，后者去掉 Unix 专用的 `VAR=value` 前缀。
4. `Import seed into D1` 报 `please use state.storage.transaction()`——seed SQL 里的显式 `BEGIN TRANSACTION` / `COMMIT` 被 D1 拒绝；去掉事务语句，空配置时直接跳过导入。

**注意**：第 4 项失败发生在 Worker **已经部署成功之后**，当时只影响安装器是否打印 `Deployment result`；`deployed: yes` 才是判断部署是否成功的关键状态，不要因为最后一步报错就重复部署。

## 已知环境现象（不是故障）

| 现象 | 说明 |
| --- | --- |
| `*.workers.dev` 无法访问 | 中国大陆网络下常被阻断；必须给 Worker 绑定自定义域名，并用该域名构造管理地址与订阅链接 |
| Cloudflare `error 1010` | 按浏览器指纹拦截 `Python-urllib` 之类明显 bot UA；真实浏览器和代理客户端 UA 正常，不影响订阅 |
| 订阅链接返回 `500 No available nodes found` | 空 Collection 的预期行为；在管理端添加第一个 Source 后 `daily` 会自动包含全部启用来源 |
| 安装器最后 4 个 curl 验证失败 | 若验证目标是 `workers.dev`，国内网络会失败，但 Worker 已上线；改用自定义域名后手动验证即可 |

## 复现验收

部署完成并绑定自定义域名后，可用下面方式复验（`<admin-token>` / `<download-token>` 从本地被 Git 忽略的 `config/agent-setup.local.json` 读取，**不要写进文档或提交**）：

```bash
curl -sS -H "User-Agent: Mozilla/5.0" \
     -H "Authorization: Bearer <admin-token>" \
     https://<自定义域名>/api/env

curl -sS -H "User-Agent: Mozilla/5.0" \
     "https://<自定义域名>/download/collection/daily/mihomo?token=<download-token>"
```

管理地址：`https://<自定义域名>/#token=<admin-token>`。前端读取后会立即把 Token 从地址栏移除。

## 后续动作

1. 在「订阅」页添加第一个 Source。
2. 复制下载链接到客户端验证输出格式。
3. 在「设置」页导出一次完整配置备份。
4. 妥善保存两个 Token，并确认 `config/agent-setup.local.json` 仍被 `.gitignore` 覆盖。
