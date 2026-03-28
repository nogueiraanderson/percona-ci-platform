// Switch EC2 clouds from InstanceProfileCredentialsProvider to
// DefaultCredentialsProvider so the patched EC2 plugin (with STS
// dependency) picks up IRSA on EKS pods.
//
// Runs AFTER cloud.groovy (alphabetical: 'e' > 'c') to override
// the hardcoded useInstanceProfileForCredentials=true.
//
// Requires: ec2 plugin with fix/eks-irsa-support patches
// (STS dependency + tryCreateWebIdentityProvider).
import jenkins.model.Jenkins
import hudson.plugins.ec2.EC2Cloud

Jenkins.instance.clouds.findAll { it instanceof EC2Cloud }.each { cloud ->
  def field = EC2Cloud.getDeclaredField("useInstanceProfileForCredentials")
  field.accessible = true
  field.set(cloud, false)
  println "EC2 IRSA: ${cloud.name} -> useInstanceProfile=false"
}
Jenkins.instance.save()

// Self-delete
new File("/var/jenkins_home/init.groovy.d/ec2-irsa-credential.groovy").delete()
