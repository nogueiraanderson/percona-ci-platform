// Switch to Jenkins own user database with no anonymous access
import jenkins.model.*
import hudson.security.*

def jenkins = Jenkins.instance

// Local user database (no signup)
jenkins.securityRealm = new HudsonPrivateSecurityRealm(false, false, null)

// Only logged-in users can access anything
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
jenkins.authorizationStrategy = strategy

jenkins.save()

// Create admin user
def realm = jenkins.securityRealm
try {
  realm.createAccount("admin", "percona-eks-poc-2026")
  println "Admin user created"
} catch (e) {
  println "Admin user already exists"
}

println "Auth: local DB, no anonymous access"

// Self-delete
new File("/var/jenkins_home/init.groovy.d/fix-auth.groovy").delete()
