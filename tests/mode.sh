#!/usr/bin/env bash
# mode 子命令：模式校验、Mixin 持久化、控制器即时切换，均不触碰宿主网络。
set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
export CLASHCTL_HOME="$WORK_DIR/home"
mkdir -p "$CLASHCTL_HOME/"{scripts,bin,data}
cp -r "$REPO_DIR/scripts/"{lib,cmd} "$CLASHCTL_HOME/scripts/"
printf '1\n' >"$CLASHCTL_HOME/.clashctl-format"
printf 'CLASHCTL_KERNEL=mihomo\nINIT_TYPE=nohup\n' >"$CLASHCTL_HOME/.env"
printf 'external-controller: "127.0.0.1:9090"\nmode: rule\n' >"$CLASHCTL_HOME/data/runtime.yaml"
printf '' >"$CLASHCTL_HOME/data/mixin.yaml"

# yq 只实现本测试用到的表达式：读取 mode / external-controller、解析 JSON 与写入 mode。
cat >"$CLASHCTL_HOME/bin/yq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLASHCTL_HOME/yq-calls"
if [ "${1:-}" = -i ]; then
    case "${2:-}" in
    '.mode = env(MODE)') printf 'mode: %s\n' "${MODE:-unset}" >"${3:-}" ;;
    *) exit 1 ;;
    esac
    exit 0
fi
# 解析控制器返回的 JSON（读实时模式）
if [ "${1:-}" = -p ] && [ "${2:-}" = json ]; then
    sed -nE 's/.*"mode"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1
    exit 0
fi
case "${1:-}" in
'.mode // ""') awk '/^mode:/{l=$0; sub(/^mode:[[:space:]]*/,"",l); gsub(/"/,"",l); print l; exit}' "${2:-}" 2>/dev/null ;;
'.external-controller // ""') awk '/^external-controller:/{l=$0; sub(/^external-controller:[[:space:]]*/,"",l); gsub(/"/,"",l); print l; exit}' "${2:-}" 2>/dev/null ;;
*) exit 1 ;;
esac
EOF
chmod +x "$CLASHCTL_HOME/bin/yq"

cat >"$CLASHCTL_HOME/scripts/lib/zz-test.sh" <<'EOF'
service_is_active() { [ -f "$CLASHCTL_HOME/running" ]; }
_get_secret() { printf 'test-secret\n'; }
# 有状态的控制器桩：PATCH 记录实时模式，GET /configs 回读该模式。
curl() {
    printf '%s\n' "$*" >>"$CLASHCTL_HOME/curl-calls"
    [ -f "$CLASHCTL_HOME/api-fail" ] && return 1
    case "$*" in
    *'-X PATCH'*)
        printf '%s\n' "$*" | sed -nE 's/.*\{"mode":"([a-z]+)"\}.*/\1/p' | head -n 1 \
            >"$CLASHCTL_HOME/live-mode"
        ;;
    */configs*)
        local m=rule
        [ -f "$CLASHCTL_HOME/live-mode" ] && m=$(cat "$CLASHCTL_HOME/live-mode")
        printf '{"mode":"%s"}\n' "$m"
        ;;
    esac
    return 0
}
EOF
# shellcheck source=/dev/null
. "$CLASHCTL_HOME/scripts/cmd/clashctl.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 1. 查看：默认取运行时配置。
clashctl mode >"$WORK_DIR/out" 2>&1 || fail 'mode 查看失败'
grep -q '当前路由模式：rule' "$WORK_DIR/out" || fail '未读到当前模式'
grep -q '可选：rule、global、direct' "$WORK_DIR/out" || fail '未提示可选值'

# 2. 非法取值必须拒绝，且不得写入 Mixin 或调用控制器。
: >"$CLASHCTL_HOME/yq-calls"
clashctl mode bridge >"$WORK_DIR/out" 2>&1 && fail '非法模式被接受'
grep -q '未知路由模式' "$WORK_DIR/out" || fail '非法模式未报错'
[ ! -s "$CLASHCTL_HOME/yq-calls" ] || fail '非法模式写入了配置'

# 3. 参数过多必须拒绝。
clashctl mode rule extra >"$WORK_DIR/out" 2>&1 && fail '多余参数被接受'
grep -q '参数错误' "$WORK_DIR/out" || fail '多余参数未报错'

# 4. 内核未运行：只持久化，不调用控制器。
: >"$CLASHCTL_HOME/curl-calls"
clashctl mode global >"$WORK_DIR/out" 2>&1 || fail '内核停用时切换失败'
grep -q 'mode: global' "$CLASH_CONFIG_MIXIN" || fail '未写入 Mixin'
grep -q '下次启动生效' "$WORK_DIR/out" || fail '未提示下次生效'
[ ! -s "$CLASHCTL_HOME/curl-calls" ] || fail '内核未运行时仍调用了控制器'

# 5. 内核运行：即时 PATCH 控制器，且请求体带目标模式。
touch "$CLASHCTL_HOME/running"
: >"$CLASHCTL_HOME/curl-calls"
clashctl mode direct >"$WORK_DIR/out" 2>&1 || fail '内核运行时切换失败'
grep -q '已切换为 direct' "$WORK_DIR/out" || fail '未提示切换成功'
grep -q -- '-X PATCH' "$CLASHCTL_HOME/curl-calls" || fail '未使用 PATCH'
grep -q '{"mode":"direct"}' "$CLASHCTL_HOME/curl-calls" || fail '请求体缺少目标模式'
grep -q 'test-secret' "$CLASHCTL_HOME/curl-calls" || fail '缺少认证头'
grep -q 'mode: direct' "$CLASH_CONFIG_MIXIN" || fail '内核运行时未持久化'

# 6. 控制器失败：保留 Mixin 写入，并提示重启后生效。
touch "$CLASHCTL_HOME/api-fail"
clashctl mode rule >"$WORK_DIR/out" 2>&1 && fail '控制器失败仍报成功'
grep -q '即时切换失败' "$WORK_DIR/out" || fail '控制器失败未提示'
grep -q 'mode: rule' "$CLASH_CONFIG_MIXIN" || fail '失败路径丢失持久化'

# 7. 切换后必须回读实时模式（API 不回写配置文件，读内存态才准）。
rm -f "$CLASHCTL_HOME/api-fail"
clashctl mode >"$WORK_DIR/out" 2>&1 || fail '切换后回读失败'
grep -q '当前路由模式：direct' "$WORK_DIR/out" || fail '切换后未回读实时模式'
# 配置文件仍是旧值时，也必须以运行时为准。
printf 'external-controller: "127.0.0.1:9090"\nmode: rule\n' >"$CLASH_CONFIG_RUNTIME"
clashctl mode >"$WORK_DIR/out" 2>&1 || fail '实时模式读取失败'
grep -q '当前路由模式：direct' "$WORK_DIR/out" || fail '配置文件覆盖了实时模式'

# 8. 帮助信息。
clashctl mode -h >"$WORK_DIR/out" 2>&1 || fail 'mode 帮助失败'
grep -q 'clashctl mode rule' "$WORK_DIR/out" || fail '帮助缺少示例'

printf 'mode: ok\n'
