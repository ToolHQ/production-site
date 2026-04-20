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

@test "_app_get_status: reports kubectl unavailable when cluster access is down" {
    run _app_get_status "demo-app" "workload" "kubectl unavailable"

    assert_success
    assert_output "kubectl unavailable"
}

@test "_app_classify_pod_status_json: distinguishes workload pod states" {
    local running_json='{"items":[{"status":{"phase":"Running","containerStatuses":[{"ready":true}]}}]}'
    local pending_json='{"items":[{"status":{"phase":"Pending"}}]}'
    local crash_json='{"items":[{"status":{"phase":"Running","containerStatuses":[{"ready":false,"state":{"waiting":{"reason":"CrashLoopBackOff"}}}]}}]}'
    local missing_json='{"items":[]}'

    run _app_classify_pod_status_json "$running_json"
    assert_success
    assert_output "Running"

    run _app_classify_pod_status_json "$pending_json"
    assert_success
    assert_output "Pending"

    run _app_classify_pod_status_json "$crash_json"
    assert_success
    assert_output "CrashLoop"

    run _app_classify_pod_status_json "$missing_json"
    assert_success
    assert_output "Missing"
}

@test "_app_run_npm_script_logged: streams output and persists npm script execution" {
    export TUI_APP_DEPLOY_LOG_DIR="$BATS_TEST_TMPDIR/tui-app-deploy"
    export MINIO_ACCESS_KEY="test-access"
    export MINIO_SECRET_KEY="test-secret"
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

@test "_app_check_static_prereqs_logged: validates real MinIO endpoint and CA bundle" {
    export TUI_APP_DEPLOY_LOG_DIR="$BATS_TEST_TMPDIR/tui-app-deploy"
    export STATIC_UPLOAD_ENDPOINT_URL="https://minio.dnor.io"
    export AWS_CA_BUNDLE="$BATS_TEST_TMPDIR/dnor-ca.crt"
    export MINIO_ACCESS_KEY="test-access"
    export MINIO_SECRET_KEY="test-secret"
    touch "$AWS_CA_BUNDLE"

    local app_dir="$BATS_TEST_TMPDIR/apps/static"
    mkdir -p "$app_dir" "$BATS_TEST_TMPDIR/bin"

    cat > "$app_dir/package.json" <<'EOF'
{
  "scripts": {
    "build-and-upload": "echo noop"
  }
}
EOF

    for cmd in node npm aws jq; do
        cat > "$BATS_TEST_TMPDIR/bin/$cmd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$BATS_TEST_TMPDIR/bin/$cmd"
    done

    cat > "$BATS_TEST_TMPDIR/bin/getent" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "hosts" ] && [ "$2" = "minio.dnor.io" ]; then
  echo "10.0.1.100 minio.dnor.io"
  exit 0
fi
exit 1
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/getent"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    local log_file
    log_file=$(_app_new_deploy_log_file "static" "build-and-upload")
    _app_init_deploy_log "$log_file" "static" "$app_dir" "npm run build-and-upload" >/dev/null

    run _app_check_static_prereqs_logged "$app_dir" "$log_file"

    assert_success
    run grep -F "Static upload endpoint: https://minio.dnor.io" "$log_file"
    assert_success
    run grep -F "OK: minio.dnor.io resolves locally" "$log_file"
    assert_success
    run grep -F "OK: CA bundle available at $AWS_CA_BUNDLE" "$log_file"
    assert_success
    run grep -F "OK: MinIO credentials available for static upload" "$log_file"
    assert_success
}

@test "_jslibs_has_publish_auth: accepts scoped npm auth entries" {
    local dir="$BATS_TEST_TMPDIR/js-libs"
    mkdir -p "$dir"

    cat > "$dir/.npmrc" <<'EOF'
registry=https://nexus.dnor.io/repository/npm-group
//nexus.dnor.io/repository/:_auth=dGVzdA==
always-auth=true
EOF

    run _jslibs_has_publish_auth "$dir"

    assert_success
}

@test "_jslibs_git_status: reports dirty worktree entries" {
    local dir="$BATS_TEST_TMPDIR/js-libs"
    mkdir -p "$dir"
    git -C "$dir" init -q

    cat > "$dir/README.md" <<'EOF'
temporary
EOF

    run _jslibs_git_status "$dir"

    assert_success
    [[ "$output" == *"?? README.md"* ]]
}

@test "_jslibs_status_rows_from_dir: reports local and Nexus versions per package" {
    local dir="$BATS_TEST_TMPDIR/js-libs"
    mkdir -p "$dir/packages/logger" "$dir/packages/httpclient"

    cat > "$dir/packages/logger/package.json" <<'EOF'
{
  "name": "@dnorio/logger",
  "version": "0.0.175"
}
EOF

    cat > "$dir/packages/httpclient/package.json" <<'EOF'
{
  "name": "@dnorio/httpclient",
  "version": "0.0.176"
}
EOF

    _jslibs_nexus_package_version() {
        case "$2" in
            "@dnorio/httpclient") echo "0.0.176" ;;
            "@dnorio/logger") echo "0.0.175" ;;
            *) echo "not found" ;;
        esac
    }

    run _jslibs_status_rows_from_dir "$dir" "secret"

    assert_success
    [[ "$output" == *"@dnorio/httpclient|0.0.176|0.0.176"* ]]
    [[ "$output" == *"@dnorio/logger|0.0.175|0.0.175"* ]]
}

@test "_jslibs_repo_status_from_json: flags missing required npm repositories" {
    local repos_json='[
      {"format":"npm","name":"npm-group","type":"group","url":"http://localhost:8081/repository/npm-group"},
      {"format":"npm","name":"npm-repo","type":"hosted","url":"http://localhost:8081/repository/npm-repo"}
    ]'

    run _jslibs_repo_status_from_json "$repos_json"

    assert_success
    [[ "$output" == *$'npm-group\tOK\tgroup\thttp://localhost:8081/repository/npm-group'* ]]
    [[ "$output" == *$'npm-repo\tOK\thosted\thttp://localhost:8081/repository/npm-repo'* ]]
    [[ "$output" == *$'npm-proxy\tMISSING\tproxy\t-'* ]]
}
