# 来源与维护说明

本仓库为**独立维护**的私有副本，不跟踪、不合并不拉取上游更新。
代码中的下载、更新、文档与反馈链接**均已指向本仓库**。

- 来源标注：上游 `clashctl` 项目 master `72d9257ce178384304b998b4fb30b07bbb5fecf3`（2026-11-25）。仅为来源说明，不作为任何运行时地址。
- 许可：MIT（见 [LICENSE](LICENSE)，原始版权声明保留）。
- 提交历史已压平为单一初始提交，未保留上游历史，未配置 upstream remote。

## 相对基线的改动

| 改动 | 说明 |
|---|---|
| 新增 `clashctl mode` | `scripts/cmd/mode.sh`：查看/切换 `rule`、`global`、`direct`；写入 Mixin 持久化，运行中通过控制器即时生效，无需重启。 |
| 新增测试 | `tests/mode.sh`：取值校验、参数校验、内核未运行、即时切换、控制器失败回退、帮助输出。 |
| 引用改指本仓库 | `install.sh`、`scripts/install-common.sh`、`scripts/preflight.sh`、`scripts/cmd/{help,update}.sh`、README、Issue 模板、`resources/mixin.yaml.example`、相关测试夹具。 |
| 文档 | `scripts/cmd/help.sh` 与 `README.md` 增加 `mode` 条目。 |
| 清理 | 移除 README 第三方赞助表格与 `FUNDING.yml` 原作者赞助链接。 |
| CI | 触发分支改为 `main`。 |

## 注意（私有仓库带来的限制）

- `clashctl update`、`install.sh` 的源码下载、以及内核/依赖二进制下载，都需要对 GitHub 具备凭据（HTTPS token 或 SSH key 或已登录的 git credential helper）；**匿名访问会 404/401**。
- `clash` 内核二进制已发布在本仓库 release `clash`（tag `clash`），名称与上游一致，`preflight.sh` 可直接拉取。
- 若希望匿名一键安装，需要把仓库改为 public，或自建镜像/代理。
