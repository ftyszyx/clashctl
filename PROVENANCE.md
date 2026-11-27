# 来源与维护说明

本仓库为**独立维护**的私有副本，不跟踪、不合并不拉取上游更新。

- 基线：`nelvko/clashctl` master `72d9257ce178384304b998b4fb30b07bbb5fecf3`（2026-11-25）
- 许可：MIT（见 [LICENSE](LICENSE)，原始版权声明保留）
- 提交历史已压平为单一初始提交，未保留上游历史，也未配置 upstream remote。

## 相对基线的改动

| 改动 | 说明 |
|---|---|
| 新增 `clashctl mode` | `scripts/cmd/mode.sh`：查看/切换 `rule`、`global`、`direct`；写入 Mixin 持久化，并对运行中的内核通过控制器即时生效，无需重启。 |
| 新增测试 | `tests/mode.sh`：覆盖取值校验、参数校验、内核未运行、即时切换、控制器失败、帮助输出。 |
| 文档 | `scripts/cmd/help.sh` 与 `README.md` 的 `mode` 条目。 |

## 注意

`clashctl update` 仍指向原上游仓库，执行会把本仓库代码替换为上游版本。
如需保留本地改动，请不要使用 `update`，改为 `git pull` 本仓库。
