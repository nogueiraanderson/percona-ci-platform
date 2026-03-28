// Switch to Jenkins own user database with no anonymous access.
// Password is read from JENKINS_ADMIN_PASSWORD env var or defaults to
// a random UUID (printed to logs on first boot).
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

// Create admin user with password from env or random
def password = System.getenv("JENKINS_ADMIN_PASSWORD") ?: UUID.randomUUID().toString()
def realm = jenkins.securityRealm
try {
  realm.createAccount("admin", password)
  println "Admin user created. Password: ${password}"
} catch (e) {
  println "Admin user already exists"
}

println "Auth: local DB, no anonymous access"

// Mark clone as initialized (prevents one-time scripts from re-running)
new File("/var/jenkins_home/.clone-initialized").text = new Date().toString()

// Self-delete
new File("/var/jenkins_home/init.groovy.d/fix-auth.groovy").delete()
