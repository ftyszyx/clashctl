#!/usr/bin/env bash

# shellcheck disable=SC1091  # 独立 source（测试）时补载依赖；经 clashctl.sh 加载时已存在。
declare -F _clashctl_run_in_bash >/dev/null 2>&1 || . "${BASH_SOURCE[0]%/*}/../lib/shell.sh"

# mihomo 只认这三种路由模式。
_MODE_VALUES='rule global direct'

# 优先读运行时配置（已生效），回退到 Mixin（尚未合并），最后按 mihomo 默认值。
_mode_current() {
    local mode
    mode=$("$BIN_YQ" '.mode // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null) || mode=''
    [ -n "$mode" ] || mode=$("$BIN_YQ" '.mode // ""' "$CLASH_CONFIG_MIXIN" 2>/dev/null) || mode=''
    [ -n "$mode" ] || mode=rule
    printf '%s\n' "$mode"
}

# 通过控制器即时切换，避免为改一个字段重启内核、中断现有连接。
_mode_api_apply() (
    local mode=$1 controller port host secret
    controller=$("$BIN_YQ" '.external-controller // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null) || return 1
    port=${controller##*:}
    case $port in '' | *[!0-9]*) return 1 ;; esac
    host=${controller%:*}
    case $host in
    '' | '*' | 0.0.0.0) host=127.0.0.1 ;;
    '[::]' | ::) host='[::1]' ;;
    *:*) [[ $host == \[* ]] || host="[$host]" ;;
    esac
    secret=$(_get_secret) || return 1
    curl --silent --fail --noproxy '*' --connect-timeout 1 --max-time 2 \
        -X PATCH \
        -H "Authorization: Bearer $secret" \
        -H 'Content-Type: application/json' \
        -d "{\"mode\":\"$mode\"}" \
        "http://$host:$port/configs" >&/dev/null
)

clashmode() {
    if ! _clashctl_in_bash; then
        _clashctl_run_in_bash clashmode "$@"
        return
    fi
    case "${1:-}" in
    -h | --help | help)
        mode_help
        return 0
        ;;
    esac

    [ $# -le 1 ] || {
        _failcat "参数错误，请使用 -h 查看帮助"
        return 1
    }

    local mode=${1:-}
    if [ -z "$mode" ]; then
        printf '当前路由模式：%s\n' "$(_mode_current)"
        printf '可选：rule、global、direct\n'
        return 0
    fi

    case " $_MODE_VALUES " in
    *" $mode "*) ;;
    *)
        _failcat "未知路由模式：$mode（可选：rule、global、direct）"
        return 1
        ;;
    esac

    # 写入 Mixin：重启、重载配置后仍然保持。
    MODE=$mode "$BIN_YQ" -i '.mode = env(MODE)' "$CLASH_CONFIG_MIXIN" || {
        _failcat "写入 Mixin 失败"
        return 1
    }

    if ! service_is_active >&/dev/null; then
        _okcat "路由模式已设为 $mode（内核未运行，下次启动生效）"
        return 0
    fi

    if ! _mode_api_apply "$mode"; then
        _failcat "已写入 Mixin，但即时切换失败；重启内核后生效（clashctl stop && clashctl start）"
        return 1
    fi

    _okcat "路由模式已切换为 $mode"
}

mode_help() {
    cat <<EOF

- 查看当前路由模式
  clashctl mode

- 切换路由模式（rule 规则 / global 全局 / direct 直连）
  clashctl mode rule
  clashctl mode global
  clashctl mode direct

EOF
}
