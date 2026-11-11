# 部署修复说明 / Deployment Fix Notes

本仓库是 [realchendahuang/sub-store-cloudflare](https://github.com/realchendahuang/sub-store-cloudflare)
的**部署修复版**，基于上游 **v1.1.0**（commit `4673e195b6fce7692f142da1e3b5ae558d45bef4`，2026-10-31）。

保留上游全部 Worker / 前端源码与业务逻辑，**只修正部署路径与文档**：把失效的一键按钮路径换成可靠的 CLI 部署，并补上部署后的配置校验。沿用 **AGPL-3.0-or-later**，`LICENSE` 与 `NOTICE` 均保留。

---

## 一、要修的问题

上游把「点击 Deploy to Cloudflare 按钮」列为首选部署方式，但当前 Cloudflare Workers Builds 的部署表单存在缺陷：

| 现象 | 后果 |
| --- | --- |
| 表单**不渲染** `wrangler.jsonc` 中 `secrets.required` 声明的 `SUB_STORE_ADMIN_TOKEN` 和 `SUB_STORE_PUBLIC_DOWNLOAD_TOKEN`（有时只显示其中一个） | 两个 Secret 没地方填，首次构建必然失败；即使靠手工补齐勉强部署，管理后台也会 401 |
| 表单反而**强制要求填写** `SUB_STORE_PUBLIC_DOWNLOAD_HOSTS` | 该 `vars` 按设计应留空（它是「仅允许访问 `/download/*` 的独立下载域名」），但 Cloudflare 表单不允许空值 |
| 在 Worker 的 Variables 页面手工补 Secret | 社区实测在首次构建阶段无效 |

这不是使用者操作失误。上游 issue
[#18「[Deploy]: 部署时要求填写的内容与文档不符?」](https://github.com/realchendahuang/sub-store-cloudflare/issues/18)
自 2026-07-17 提出，截至 2026-10-22 仍处于 open 状态，作者未在该帖内给出修复。同类问题 [#16](https://github.com/realchendahuang/sub-store-cloudflare/issues/16)（错误声明 `SUB_STORE_BOOTSTRAP_SOURCE_CONTENT`）已由作者修复并关闭，但 #18 没有。

社区验证过的临时解法（首次构建失败后进 Worker 设置页补 Secret、或改用 Legacy pages workflow 旧入口）都不可靠，因此本仓库不再把按钮路径作为推荐路径。

**根因判断**：`secrets.required` 是部署表单的提示字段，而新版 Workers Builds 表单主要渲染 `vars`，对 Secret 声明的处理发生了变化；上游为了防止 Cloudflare 把公开占位字符串当成「可直接使用的默认 Secret」，刻意不提供根目录 `.dev.vars.example`，因此也没有兜底输入框。这是平台侧行为变化，改项目配置无法可靠修好。

---

## 二、修补清单

| 文件 | 类型 | 内容 |
| --- | --- | --- |
| `scripts/install-fixed.sh` | 新增 | Linux / macOS / Git Bash 一键部署脚本：前置检查 → Corepack → 依赖与脚本注册表 → Cloudflare 登录 → `install:quick` → Token 校验 |
| `scripts/install-fixed.ps1` | 新增 | Windows PowerShell 版一键脚本，逻辑同上；额外自动探测不在 PATH 中的 `node.exe` / `corepack.cmd` / `git.exe`，并把所在目录注入当前会话 PATH |
| `scripts/install-cloudflare.mjs` | 修改 | **Windows 兼容补丁**：上游安装器用 `spawnSync("pnpm", ...)`，而 Corepack 在 Windows 上只提供 `pnpm.CMD` / `pnpm.ps1`，Node 直接调用会 `ENOENT` / `EINVAL`，导致第一步就报 `pnpm is required.`。本版在 Windows 上改为用 `process.execPath` 直调 Corepack 的 `node_modules/corepack/dist/pnpm.js`，无需 shell、无需 PATH 解析，`wrangler secret put` 的 stdin 传递也保持正常；非 Windows 行为完全不变 |
| `scripts/verify-secrets.mjs` | 新增 | 部署后校验 `config/agent-setup.local.json`：两个 Token 都存在、互不相同、长度足够，并提示妥善保管 |
| `package.json` | 修改 | **Windows 兼容**：`build:frontend` 原为 `VITE_API_URL=/ pnpm ...`，Unix 专用语法在 Windows 的 cmd.exe 下报「'VITE_API_URL' 不是内部或外部命令」。前端 `useHostAPI.ts` 本来就以 `/` 为默认值，去掉前缀后行为完全等价且跨平台 |
| `cloudflare/src/worker-configuration.d.ts` | 修改 | 用当前锁定的 Wrangler 4.159.0 重新生成。上游提交的文件带旧版 `wrangler types` 的 hash，`types:check` 会报 `Types ... are out of date`，导致安装器的 `pnpm run check` 中断 |
| `frontend/README.md` | 修改 | 同步说明 `VITE_API_URL` 可省略及其原因 |
| `docs/deploy-fix.zh-CN.md` | 新增 | 完整中文部署指南：前置条件、一键/手动命令、Token 保管、自定义域名（国内 `workers.dev` 不可直连）、验证清单、升级、常见问题、兼容边界 |
| `PATCH_NOTES.md` | 新增 | 本文件 |
| `README.md` | 修改 | 顶部加「部署修复版」声明，并标注上游原文中「最快部署：三步完成」一节在当前表单下已失效 |
| `docs/deployment.md` | 修改 | 第 1 节「Cloudflare 官方一键部署」加醒目已知问题警告，指向第 2 节 CLI 路径 |
| `docs/troubleshooting.md` | 修改 | 新增「Deploy to Cloudflare 表单 Secret 缺失」排查小节 |
| `NOTICE` | 修改 | 追加派生说明、上游 commit 与「未改动 Worker 运行时逻辑」的声明 |

**没有改动**：`wrangler.jsonc`、`cloudflare/src/**` 里的业务代码、`frontend/src/**`、`config/**` 以及任何 Worker 运行时逻辑。被修改的上游文件只有 4 类：部署安装器（`commandSpec()` 一层命令解析，Linux / macOS 走原路径不变）、根 `package.json` 的构建脚本、一个自动生成的类型声明文件、以及文档。这样以后合并上游更新时冲突面最小。

---

## 三、为什么不这样修（设计决策）

1. **不新增根目录 `.dev.vars.example`。** 它确实可能让 Cloudflare 表单生成 Secret 输入框，但上游的 `docs/troubleshooting.md` 与 `docs/deployment.md` 已明确说明：表单会把示例值预填成默认 Secret。用户若不逐项替换就点部署，线上会带着一个公开可猜的 admin token 裸奔。收益远小于风险，上游删掉它是正确的。
2. **不把两个 Secret 挪进 `vars`。** `vars` 是明文环境变量，会被写进仓库配置和构建日志；把鉴权 Token 放进去是安全倒退。
3. **不改 `wrangler.jsonc` 的 `secrets.required`。** 声明本身是正确的，坏的是表单渲染；CLI 路径（上游 `scripts/install-cloudflare.mjs`）会正确读取并 `wrangler secret put` 两个值。
4. **不引入 GitHub Actions / CI/CD。** 上游已刻意移除 `.github` 自动化，保持最小差异。
5. **不修 Worker 业务代码。** 本次问题只在部署链路，改运行时只会增加与上游分叉的风险。

---

## 四、合并上游更新

本仓库的改动集中在少数文件，合并上游时通常不会冲突：

```bash
git remote add upstream https://github.com/realchendahuang/sub-store-cloudflare.git
git fetch upstream --tags
git merge upstream/main
```

需要留意的文件只有 `README.md`、`README.en.md`、`NOTICE`、`docs/deployment.md`、`docs/troubleshooting.md` 和 `scripts/install-cloudflare.mjs`（若上游也改了安装器，把 `commandSpec()` 与三处 `spawnSync` 调用重新套用即可）；新增的 `PATCH_NOTES.md`、`docs/deploy-fix.zh-CN.md`、`scripts/install-fixed.*`、`scripts/verify-secrets.mjs` 不与上游冲突。

---

## 五、验证方式

不接触线上资源即可做的静态检查：

```bash
bash -n scripts/install-fixed.sh
node --check scripts/verify-secrets.mjs
node --check scripts/install-cloudflare.mjs
node scripts/install-cloudflare.mjs --doctor
```

`--doctor` 只检查 Node / pnpm / curl / Wrangler、Cloudflare 登录状态与本地配置，**不会创建或部署任何线上资源**，适合在 Windows 上验证 pnpm 调用链是否修好。

部署完成后的验收清单见 [中文部署指南](docs/deploy-fix.zh-CN.md#部署后验收)。上游自带的安装器本身也会在部署后 curl 验证 `/api/env`、`/api/templates`、`/api/sources`、`/api/collections` 四个接口。

---

## 六、许可与归属

- 上游项目：[realchendahuang/sub-store-cloudflare](https://github.com/realchendahuang/sub-store-cloudflare)，AGPL-3.0-or-later
- 更上游的灵感来源：[sub-store-org/Sub-Store](https://github.com/sub-store-org/Sub-Store)
- 本派生版本同样以 AGPL-3.0-or-later 发布，`LICENSE` 原文未改动，`NOTICE` 保留了上游归属并追加了派生说明。
- 本项目不收集、不上传任何订阅地址、节点信息或 Token。请勿把 `config/agent-setup.local.json`、订阅 URL 或 Worker Secret 提交到仓库或贴到公开场合。
