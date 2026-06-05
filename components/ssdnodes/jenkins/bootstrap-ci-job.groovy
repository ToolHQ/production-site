// bootstrap-ci-job.groovy — multibranch production-site (executar via seed_jenkins_ci_job.sh)

import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret
import jenkins.branch.*
import jenkins.plugins.git.*
import jenkins.plugins.git.traits.*
import org.jenkinsci.plugins.workflow.multibranch.*

def jenkins = Jenkins.getInstance()
def sonarToken = System.getenv('SONAR_TOKEN') ?: ''
def githubToken = System.getenv('GITHUB_TOKEN') ?: ''

// Credenciais já injetadas via JCasC; reforço se env presente
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

def gitSource = new GitSCMSource('production-site-git', 'https://github.com/ToolHQ/production-site.git', 'github-pat', '*', '', false)
gitSource.setTraits([new BranchDiscoveryTrait()])

def branchSource = new BranchSource(gitSource)
job.getSourcesList().clear()
job.getSourcesList().add(branchSource)

def factory = new WorkflowBranchProjectFactory()
factory.setScriptPath('components/ssdnodes/jenkins/Jenkinsfile.generic')
job.setProjectFactory(factory)
job.save()
job.scheduleBuild2(0)
println('[seed] multibranch production-site OK')
