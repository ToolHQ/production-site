#!/usr/bin/env bash
# seed_jenkins_deploy_ref_jobs.sh — cria 8 jobs dedicados de deploy com REF (branch/hash)
# Cada job: APP fixo (default), REF livre, TARGET choice, DRY_RUN bool, 50 logs
set -euo pipefail

JENKINS_URL="https://jenkins.ssdnodes.dnor.io"

get_jenkins_creds() {
  local token
  token=$(kubectl get secret -n jenkins jenkins -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | base64 -d 2>/dev/null) || true
  if [ -n "$token" ]; then
    echo "admin:${token}"
    return 0
  fi
  token=$(kubectl get secret -n jenkins jenkins -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null) || true
  if [ -n "$token" ]; then
    echo "admin:${token}"
    return 0
  fi
  if [ -f ~/ssdnodes-ci-platform-credentials.txt ]; then
    local user pass
    user=$(grep -i 'jenkins_user' ~/ssdnodes-ci-platform-credentials.txt | cut -d= -f2 | tr -d ' "') || true
    pass=$(grep -i 'jenkins_pass\|jenkins_token\|jenkins_api' ~/ssdnodes-ci-platform-credentials.txt | cut -d= -f2 | tr -d ' "') || true
    if [ -n "$user" ] && [ -n "$pass" ]; then
      echo "${user}:${pass}"
      return 0
    fi
  fi
  return 1
}

CREDS=$(get_jenkins_creds) || {
  echo "ERROR: Não foi possível obter credenciais Jenkins."
  echo "Configure em ~/ssdnodes-ci-platform-credentials.txt ou garanta acesso K8s."
  exit 1
}

JOBS=(
  "deploy-rs-observability-api:rs-observability-api"
  "deploy-agent-meter:agent-meter"
  "deploy-ai-radar:ai-radar"
  "deploy-gta-vi:gta-vi"
  "deploy-tor:tor"
  "deploy-py-back-end:py-back-end"
  "deploy-back-end:back-end"
  "deploy-rs-axum-back-end:rs-axum-back-end"
)

for job_entry in "${JOBS[@]}"; do
  job_name="${job_entry%%:*}"
  app="${job_entry##*:}"

  crumb=$(curl -s -u "$CREDS" "${JENKINS_URL}/crumbIssuer/api/json" 2>/dev/null)
  crumb_field=$(echo "$crumb" | python3 -c "import sys,json; print(json.load(sys.stdin).get('crumbRequestField',''))" 2>/dev/null) || true
  crumb_value=$(echo "$crumb" | python3 -c "import sys,json; print(json.load(sys.stdin).get('crumb',''))" 2>/dev/null) || true

  xml=$(cat <<XMLEOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@1581.ve4b_d0db_fcb_b_b_">
  <description>Deploy ${app} — REF (branch/hash), TARGET, DRY_RUN</description>
  <displayName>${job_name}</displayName>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>APP</name>
          <description>App do deploy-catalog.yaml</description>
          <defaultValue>${app}</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>REF</name>
          <description>Branch (main, feat/foo) ou commit hash (abc1234f)</description>
          <defaultValue>main</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.ChoiceParameterDefinition>
          <name>TARGET</name>
          <description>Cluster alvo</description>
          <choices>
            <string>oci</string>
            <string>ssdnodes</string>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>DRY_RUN</name>
          <description>true = plan only, false = execute deploy</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
    <jenkins.model.BuildDiscarderProperty>
      <strategy class="hudson.tasks.LogRotator">
        <daysToKeep>-1</daysToKeep>
        <numToKeep>50</numToKeep>
        <artifactDaysToKeep>-1</artifactDaysToKeep>
        <artifactNumToKeep>-1</artifactNumToKeep>
        <removeLastBuild>false</removeLastBuild>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@4331.v9d06ed4658ff">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@5.10.1">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <name>origin</name>
          <refspec>+refs/heads/*:refs/remotes/origin/*</refspec>
          <url>https://github.com/ToolHQ/production-site.git</url>
          <credentialsId>github-pat</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>components/ssdnodes/jenkins/Jenkinsfile.deploy-ref</scriptPath>
    <lightweight>false</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XMLEOF
)

  http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$CREDS" "${JENKINS_URL}/job/${job_name}/api/json" 2>/dev/null)

  if [ "$http_code" = "200" ]; then
    echo "  Atualizando ${job_name}..."
    curl_args=(-u "$CREDS" -X PUT "${JENKINS_URL}/job/${job_name}/config.xml" -H "Content-Type: application/xml")
    if [ -n "$crumb_field" ] && [ -n "$crumb_value" ]; then
      curl_args+=(-H "${crumb_field}: ${crumb_value}")
    fi
    curl_args+=(--data-binary "$xml")
    curl -s "${curl_args[@]}" >/dev/null
  else
    echo "  Criando ${job_name}..."
    curl_args=(-u "$CREDS" -X POST "${JENKINS_URL}/createItem?name=${job_name}" -H "Content-Type: application/xml")
    if [ -n "$crumb_field" ] && [ -n "$crumb_value" ]; then
      curl_args+=(-H "${crumb_field}: ${crumb_value}")
    fi
    curl_args+=(--data-binary "$xml")
    curl -s "${curl_args[@]}" >/dev/null
  fi
done

echo ""
echo "Jobs criados/atualizados:"
for job_entry in "${JOBS[@]}"; do
  job_name="${job_entry%%:*}"
  echo "  ${JENKINS_URL}/job/${job_name}/"
done
