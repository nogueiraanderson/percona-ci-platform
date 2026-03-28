// Configure EC2 clouds to use IRSA credentials on EKS.
//
// KNOWN ISSUE: The EC2 plugin's AWSCredentialsImpl does not support
// empty access keys (throws NullPointerException on startup).
// The plugin uses InstanceProfileCredentialsProvider when
// useInstanceProfileForCredentials=true, which resolves to the
// EKS node IAM role (not the pod's IRSA role).
//
// WORKAROUND OPTIONS:
//   1. Attach the jenkins EC2 policy to the EKS node instance role
//   2. Create a Jenkins credential with actual IAM access key/secret
//      (less ideal, but works with the current plugin)
//   3. Wait for EC2 plugin to support DefaultCredentialsProvider
//      which would pick up IRSA automatically
//
// This script is a placeholder. Uncomment and adapt when a solution
// is chosen.
//
// import hudson.plugins.ec2.*
// Jenkins.instance.clouds.findAll { it.class.simpleName == "EC2Cloud" }.each { cloud ->
//   def fieldCred = EC2Cloud.getDeclaredField("credentialsId")
//   fieldCred.accessible = true
//   fieldCred.set(cloud, "your-credential-id")
//   println "${cloud.name}: credentialsId set"
// }
// Jenkins.instance.save()

println "EC2 IRSA credential: not applied (see script comments for options)"

// Self-delete
new File("/var/jenkins_home/init.groovy.d/ec2-irsa-credential.groovy").delete()
