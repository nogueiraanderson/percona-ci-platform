// Set Jenkins URL to the EKS POC domain
import jenkins.model.*

def loc = JenkinsLocationConfiguration.get()
loc.url = "https://ps57-k8s.cd.percona.com/"
loc.save()
println "Jenkins URL set to: ${loc.url}"

// Self-delete
new File("/var/jenkins_home/init.groovy.d/fix-url.groovy").delete()
