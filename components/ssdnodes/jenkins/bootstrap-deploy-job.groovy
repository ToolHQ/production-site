// bootstrap-deploy-job.groovy — Pipeline job deploy-apps (T-348)

import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.GitSCM
import hudson.plugins.git.UserRemoteConfig

def jenkins = Jenkins.getInstance()
def jobName = 'deploy-apps'

def job = jenkins.getItem(jobName)
if (job == null) {
  job = jenkins.createProject(WorkflowJob, jobName)
}
job.setDisplayName('deploy-apps (citools)')
job.setDescription('Deploy pontual — parâmetros APP + TARGET. Ver T-348 / deploy-catalog.yaml')

def scm = new GitSCM(
  [new UserRemoteConfig('https://github.com/ToolHQ/production-site.git', 'github-pat', 'origin', '+refs/heads/*:refs/remotes/origin/*')],
  [new BranchSpec('refs/remotes/origin/feat/t-341-ssdnodes-ci-platform'), new BranchSpec('refs/remotes/origin/main')],
  null,
  null,
  null
)

job.setDefinition(new CpsScmFlowDefinition(scm, 'components/ssdnodes/jenkins/Jenkinsfile.deploy'))
job.save()
println('[seed] deploy-apps OK — build with parameters (APP, TARGET, DRY_RUN)')
