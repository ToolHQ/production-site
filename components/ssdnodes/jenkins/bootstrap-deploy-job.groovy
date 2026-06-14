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
job.setDescription('Deploy pontual — APP + TARGET + DRY_RUN. Blue Ocean: /blue/organizations/jenkins/deploy-apps/activity')

def scm = new GitSCM(
  [new UserRemoteConfig('https://github.com/ToolHQ/production-site.git', 'origin', '+refs/heads/*:refs/remotes/origin/*', 'github-pat')],
  [new BranchSpec('origin/feat/t-341-ssdnodes-ci-platform')],
  null,
  null,
  null
)

job.setDefinition(new CpsScmFlowDefinition(scm, 'components/ssdnodes/jenkins/Jenkinsfile.deploy'))
job.save()
println('[seed] deploy-apps OK — build with parameters (APP, TARGET, DRY_RUN)')
