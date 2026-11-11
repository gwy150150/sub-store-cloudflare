# 中文部署指南（修复版）

本指南对应本仓库修正后的部署路径。为什么弃用 `Deploy to Cloudflare` 按钮，见 [PATCH_NOTES.md](../PATCH_NOTES.md)。

## 为什么用 CLI

上游的按钮路径依赖 Cloudflare 部署表单渲染两个 Worker Secret，而当前表单做不到，首次构建必然失败。CLI 路径使用上游自带的 `scripts/install-cloudflare.mjs`，它会：

- 自动生成两个**不同**的随机 Token（若未预先配置）；
- 用 `wrangler secret put` 把 `SUB_STORE_ADMIN_TOKEN` 和 `SUB_STORE_PUBLIC_DOWNLOAD_TOKEN` 都写进 Worker；
- 创建或复用 D1、执行 migrations、构建前端、部署 Worker；
- 部署后 curl 验证 `/api/env`、`/api/templates`、`/api/sources`、`/api/collections`；
- 打印 `Admin URL: <地址>/#token=<adminToken>` 与下载链接。

这条路径走 `wrangler login` 的浏览器 OAuth，**不需要 GitHub App 授权**，也绕开了「GitHub authorization has expired」这类问题。

## 前置条件

| 项 | 要求 |
| --- | --- |
| Node.js | 22 或更高（`node --version`） |
| Git | 任意较新版本 |
| Corepack | Node 22 自带，`corepack --version` |
| curl | 安装器用它做部署后 HTTP 验证 |
| Cloudflare 账号 | 免费版即可；需要 Workers + D1 权限 |

不需要 KV、R2、Durable Objects、Queues 或 Cron。

## 方式一：一键脚本

Linux / macOS / Windows Git Bash：

```bash
bash scripts/install-fixed.sh
```

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-fixed.ps1
```

脚本会依次做前置检查、启用 pnpm、安装依赖、检查/唤起 Cloudflare 登录、运行安装器、校验 Token。中途失败可以直接重跑，安装器会复用本地保存的 D1 ID 和 Token，不会重复建库。

Windows 版会自动探测 `node.exe`、`corepack.cmd`、`git.exe` 的常见安装位置（包括 WorkBuddy 自带的 Node / PortableGit），并把所在目录注入当前会话的 PATH——即使这些工具没加进系统 PATH 也能运行。找不到时会明确报错并给出处理提示。

## 方式二：手动执行

顺序不要调整——安装器开头会检查 `node / pnpm / curl`，且 `pnpm run setup` 必须发生在 `wrangler login` 之前（否则 wrangler 还没装好）：

```bash
git clone https://github.com/<你的账号>/<你的仓库>.git
cd <你的仓库>
corepack enable
pnpm run setup
pnpm --dir cloudflare exec wrangler login
pnpm run install:quick
```

`install:quick` 部署的是空应用，之后在网页管理界面里添加订阅源。想在部署时一并导入订阅源，可以改用交互式安装器 `pnpm run install:cloudflare`，或先编辑 `config/agent-setup.local.json` 再运行。

无图形界面的服务器上无法完成浏览器 OAuth，改用 API Token：

```bash
export CLOUDFLARE_API_TOKEN=<有 Workers 与 D1 编辑权限的 token>
export CLOUDFLARE_ACCOUNT_ID=<账户 ID>
pnpm run install:quick
```

## 部署后验收

1. 安装器输出 `Deployment result`，四个 `/api/*` 校验全部 `Verified`。
2. 打开打印出的 `Admin URL: .../#token=<adminToken>`，能看到三步引导。
   - 前端优先读 `#token=`，同时也兼容旧的 `?token=`；hash 不会发送到服务器，优先用 `#token=`。
   - Token 会被前端从地址栏移除并存入浏览器 localStorage。若显示「数据加载失败」，确认用的是 **admin token**，不是 download token。
3. 在「订阅」页添加第一个 Source（远程订阅 URL 或本地节点文本），ID 用小写字母、数字、`_` 或 `-`。
4. 确认预置的 `Daily` Collection；模板可选 `acl4ssr-mihomo`。起步建议只加「清理信息节点 / 端点去重 / 名称排序」，别急着加地区 include 过滤器。
5. 复制下载链接验证，形如：

   ```
   https://<域名>/download/collection/<id>/mihomo?token=<DOWNLOAD_TOKEN>
   ```

   `mihomo` 可换 `sing-box` / `surge` / `loon` / `qx` / `uri`；不写 target 时按客户端 User-Agent 自动判断，认不出默认 Mihomo。

6. 在「设置」页**导出一次完整配置备份**。

## 必须做的两件事

**保管 Token。** 把 `Admin URL` 和两个 Token 存进密码管理器。`config/agent-setup.local.json` 里有明文 Token，已被 `.gitignore` 覆盖，不要提交、不要贴到 issue 或聊天群。两个 Token 职责不同：

- `SUB_STORE_ADMIN_TOKEN`：管理界面和 `/api/*`
- `SUB_STORE_PUBLIC_DOWNLOAD_TOKEN`：客户端订阅链接 `/download/*`

**绑定自定义域名。** `*.workers.dev` 在中国大陆无法直连，客户端订阅会失败。在 Cloudflare 控制台 → Workers & Pages → 该 Worker → Settings → Domains & Routes → Add Custom Domain，绑定托管在 CF 上的域名，证书自动签发。之后把下载链接换成这个域名。

注意 `SUB_STORE_PUBLIC_DOWNLOAD_HOSTS` 应留空；它表示「只允许访问 `/download/*` 的独立下载域名」，只有确实要分离下载域名时才填。填了管理域名可能导致管理端被拒。

## 升级

```bash
git pull --ff-only
corepack enable
pnpm run install:quick
```

安装器复用 `config/agent-setup.local.json` 里的 D1 ID 与 Token，migration 是向前兼容的，不会清空 Sources / Collections / Templates。升级前先在「设置」页导出备份。

如果你是从上游 Deploy Button 导入的仓库副本，那个副本不会自动合并上游新版本，正确做法是 `git remote add upstream ... && git merge upstream/main && git push`；**不要重新点一次按钮**，那会造出第二套 Worker、D1 和 Token。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| 下载链接 401 | 用了 admin token，换成 download token |
| 输出格式不对 | 链接里显式加 `/mihomo`、`/sing-box` 等 target |
| 改了配置没生效 | 远程订阅默认边缘缓存 300 秒，链接加 `&refresh=1` 强刷，或在「设置 → 请求设置」把 TTL 设 0 |
| 节点全被过滤 | 先移除地区 include 过滤器，只保留 `clean-provider-nodes`、`dedupe-by-endpoint`、`sort-by-name` |
| Wrangler 没登录 | `pnpm --dir cloudflare exec wrangler login` 后重跑脚本 |
| 安装器第一行就报 `pnpm is required.` / `ENOENT` | Windows 特有：上游安装器用 `spawnSync("pnpm")`，但 Corepack 只生成 `pnpm.CMD` / `pnpm.ps1`，Node 子进程调用不到。**本修复版已修好**（Windows 下由 `node.exe` 直调 Corepack 的 `pnpm.js`）。若你从旧提交克隆，先 `git pull --ff-only`；可用 `node scripts/install-cloudflare.mjs --doctor` 验证，正常应显示 `> pnpm: 11.7.0` |
| `wrangler types` 报 `Types ... are out of date` | 上游提交的类型声明文件带旧版 hash。本修复版已用 Wrangler 4.159.0 重新生成；若自行升级了 Wrangler，跑 `pnpm --dir cloudflare run types` 再重跑脚本 |
| 构建报 `'VITE_API_URL' 不是内部或外部命令` | 上游 `build:frontend` 用了 Unix 专用的 `VAR=value command` 前缀。本修复版已去掉（前端默认就是 `/`）；若从旧提交克隆，先 `git pull --ff-only` |
| `Import seed into D1` 报 `please use state.storage.transaction()` | 上游 seed SQL 里写了 `BEGIN TRANSACTION;` / `COMMIT;`，D1 不允许显式事务。本修复版已去掉；空配置时安装器也会直接跳过导入 |
| 部署日志显示 `deployed: yes` 但最后验证失败 | 只要看到 `Uploaded <worker>` 和 `Deployed ... triggers`，Worker 就已经上线。最后 4 个 curl 是访问 `*.workers.dev`，国内网络常连不上；不影响部署结果，绑好自定义域名即可 |
| 只诊断不部署 | `pnpm run install:doctor` |

## 免费版边界与兼容边界

- Workers Free：10 ms CPU/请求、50 个 subrequest/请求。本项目按免费版设计验证，但订阅源很多时仍需留意。
- Cloudflare 出站 IP 在境外，限制中国大陆 IP 的订阅源可能拉不动。
- 相对原版 Node.js Sub-Store，本项目**不提供**：通用文件托管、Artifact 定时生成、Gist / GitLab / 第三方同步、运行时与远程 JavaScript 脚本、D1 持久请求日志、多用户账号。自定义 JS Filter / Operator 只支持构建时打包，需通过 CLI 重新部署。
- 原版 Node 版的备份 JSON **不能直接导入**（D1 schema 不同，且本项目明确不做完整上游 API 兼容层）。订阅源需要重新录入，或写进 `config/agent-setup.local.json` 后用 `pnpm run seed:remote` 批量导入。

完整兼容矩阵见 [upstream-compatibility.md](upstream-compatibility.md)，产品边界见 [product-scope.md](product-scope.md)。
