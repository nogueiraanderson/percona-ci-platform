// Set Jenkins URL from JENKINS_URL env var.
// Falls back to existing URL if env var is not set.
import jenkins.model.*

def newUrl = System.getenv("JENKINS_URL")
if (newUrl) {
  if (!newUrl.endsWith("/")) newUrl += "/"
  def loc = JenkinsLocationConfiguration.get()
  loc.url = newUrl
  loc.save()
  println "Jenkins URL set to: ${newUrl}"
} else {
  println "JENKINS_URL env var not set, keeping existing URL"
}

// Self-delete
new File("/var/jenkins_home/init.groovy.d/fix-url.groovy").delete()
