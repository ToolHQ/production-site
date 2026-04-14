#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    export __TESTING_MODE=true
    source "$BATS_TEST_DIRNAME/../k8s_ops_menu.sh" >/dev/null 2>&1
}


@test "calculate_age_seconds: converts seconds diff to human readable" {
    run format_age 30
    assert_output "30s"
    
    run format_age 120
    assert_output "2m"
    
    run format_age 3660
    assert_output "1h"
    
    run format_age 90000
    assert_output "1d"
}

@test "parse_ingress_data: extract correct controller info" {
    # Mock input similar to kubectl output
    local input="kube-system|kube-dns|dns:53,dns-tcp:53,
ingress-nginx|ingress-nginx-controller|http:31234,https:32456,
default|kubernetes|https:443,"
    
    run parse_ingress_data "$input"
    assert_success
    assert_output "ingress-nginx|ingress-nginx-controller|http:31234,https:32456,"
}

@test "_app_new_deploy_log_file: creates deterministic host log path" {
    export TUI_APP_DEPLOY_LOG_DIR="$BATS_TEST_TMPDIR/tui-app-deploy"

    run _app_new_deploy_log_file "my-site-nginx" "publish.sh"

    assert_success
    [[ "$output" == "$TUI_APP_DEPLOY_LOG_DIR"/*_my-site-nginx_publish.log ]]
    [ -d "$TUI_APP_DEPLOY_LOG_DIR" ]
}

@test "_app_run_deploy_logged: streams output and persists stdout/stderr with exit code" {
    export TUI_APP_DEPLOY_LOG_DIR="$BATS_TEST_TMPDIR/tui-app-deploy"
    local app_dir="$BATS_TEST_TMPDIR/apps/demo-app"
    mkdir -p "$app_dir"
    printf '#!/usr/bin/env bash\necho "hello stdout"\necho "hello stderr" >&2\nexit 7\n' > "$app_dir/deploy.sh"
    chmod +x "$app_dir/deploy.sh"

    local log_file
    log_file=$(_app_new_deploy_log_file "demo-app" "deploy.sh")
    _app_init_deploy_log "$log_file" "demo-app" "$app_dir" "$app_dir/deploy.sh" >/dev/null

    run _app_run_deploy_logged "demo-app" "$app_dir" "$app_dir/deploy.sh" "$log_file"

    assert_failure 7
    [[ "$output" == *"hello stdout"* ]]
    [[ "$output" == *"hello stderr"* ]]
    [ -f "$log_file" ]

    run grep -F "hello stdout" "$log_file"
    assert_success
    run grep -F "hello stderr" "$log_file"
    assert_success
    run grep -F "Exit code: 7" "$log_file"
    assert_success
}

@test "_app_get_status: static apps return static/minio" {
    run _app_get_status "" "static"

    assert_success
    assert_output "static/minio"
}

@test "_app_run_npm_script_logged: streams output and persists npm script execution" {
    export TUI_APP_DEPLOY_LOG_DIR="$BATS_TEST_TMPDIR/tui-app-deploy"
    local app_dir="$BATS_TEST_TMPDIR/apps/static"
    mkdir -p "$app_dir" "$BATS_TEST_TMPDIR/bin"

    cat > "$app_dir/package.json" <<'EOF'
{
  "scripts": {
    "build-and-upload": "echo noop"
  }
}
EOF

    cat > "$BATS_TEST_TMPDIR/bin/npm" <<'EOF'
#!/usr/bin/env bash
echo "npm mocked: $*"
echo "static upload ok" >&2
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/npm"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    local log_file
    log_file=$(_app_new_deploy_log_file "static" "build-and-upload")
    _app_init_deploy_log "$log_file" "static" "$app_dir" "npm run build-and-upload" >/dev/null

    run _app_run_npm_script_logged "static" "$app_dir" "build-and-upload" "$log_file"

    assert_success
    [[ "$output" == *"npm mocked: run build-and-upload"* ]]
    [[ "$output" == *"static upload ok"* ]]
    [ -f "$log_file" ]

    run grep -F "npm mocked: run build-and-upload" "$log_file"
    assert_success
    run grep -F "static upload ok" "$log_file"
    assert_success
    run grep -F "Exit code: 0" "$log_file"
    assert_success
}
