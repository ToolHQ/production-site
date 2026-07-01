// bootstrap-agent-meter-oss-job.groovy — multibranch dnorio/agent-meter (T-365)

import jenkins.model.Jenkins
import jenkins.branch.*
import org.jenkinsci.plugins.workflow.multibranch.*
import org.jenkinsci.plugins.github_branch_source.GitHubSCMSource
import org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait
import org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait

def jenkins = Jenkins.getInstance()
def jobName = 'agent-meter-oss'
def job = jenkins.getItem(jobName)
if (job == null) {
  job = jenkins.createProject(WorkflowMultiBranchProject, jobName)
}
job.setDisplayName('agent-meter OSS')
job.setDescription('Multibranch CI for dnorio/agent-meter — status jenkins/agent-meter')

def ghSource = new GitHubSCMSource('dnorio', 'agent-meter')
ghSource.setId('agent-meter-oss-gh')
ghSource.setCredentialsId('github-pat')
ghSource.setTraits([
  new BranchDiscoveryTrait(1),
  new OriginPullRequestDiscoveryTrait(1),
])

def branchSource = new BranchSource(ghSource)
job.getSourcesList().clear()
job.getSourcesList().add(branchSource)

def factory = new WorkflowBranchProjectFactory()
factory.setScriptPath('Jenkinsfile')
job.setProjectFactory(factory)
job.save()
job.scheduleBuild2(0)
println('[seed] multibranch agent-meter-oss OK (dnorio/agent-meter)')
