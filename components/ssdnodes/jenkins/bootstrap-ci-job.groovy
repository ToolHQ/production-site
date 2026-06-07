// bootstrap-ci-job.groovy — multibranch production-site (GitHubSCMSource + webhook T-345)

import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret
import jenkins.branch.*
import org.jenkinsci.plugins.workflow.multibranch.*
import org.jenkinsci.plugins.github_branch_source.GitHubSCMSource
import org.jenkinsci.plugins.github_branch_source.BranchDiscoveryTrait
import org.jenkinsci.plugins.github_branch_source.OriginPullRequestDiscoveryTrait

def jenkins = Jenkins.getInstance()
def sonarToken = System.getenv('SONAR_TOKEN') ?: ''
def githubToken = System.getenv('GITHUB_TOKEN') ?: ''

if (githubToken) {
  def domain = Domain.global()
  def store = jenkins.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()
  def upsertString = { id, desc, secret ->
    if (!secret) return
    def creds = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials(
      org.jenkinsci.plugins.plaincredentials.StringCredentials.class, jenkins, null, null)
    creds.findAll { it.id == id }.each { store.removeCredentials(domain, it) }
    store.addCredentials(domain, new StringCredentialsImpl(CredentialsScope.GLOBAL, id, desc, Secret.fromString(secret)))
  }
  upsertString('sonar-token', 'SonarQube CI', sonarToken)
  upsertString('github-pat', 'GitHub PAT', githubToken)
  println('[seed] credentials refreshed from env')
} else {
  println('[seed] using JCasC credentials (github-pat)')
}

def jobName = 'production-site'
def job = jenkins.getItem(jobName)
if (job == null) {
  job = jenkins.createProject(WorkflowMultiBranchProject, jobName)
}
job.setDisplayName('production-site (citools)')
job.setDescription('Multibranch CI citools. Blue Ocean: /blue/organizations/jenkins/production-site/activity')

// manageHooks=false — webhook via configure_github_ci_protection.sh
def ghSource = new GitHubSCMSource('ToolHQ', 'production-site')
ghSource.setId('production-site-gh')
ghSource.setCredentialsId('github-pat')
ghSource.setTraits([
  new BranchDiscoveryTrait(1),
  new OriginPullRequestDiscoveryTrait(1),
])

def branchSource = new BranchSource(ghSource)
job.getSourcesList().clear()
job.getSourcesList().add(branchSource)

def factory = new WorkflowBranchProjectFactory()
factory.setScriptPath('components/ssdnodes/jenkins/Jenkinsfile.generic')
job.setProjectFactory(factory)
job.save()
job.scheduleBuild2(0)
println('[seed] multibranch production-site OK (GitHubSCMSource)')
