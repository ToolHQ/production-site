#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    export __TESTING_MODE=true
    source "./k8s_ops_menu.sh"
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
