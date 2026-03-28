// Remove all TimerTrigger (cron) from jobs to prevent
// the cloned instance from running builds that conflict
// with the original ps57
import hudson.triggers.*

def disabled = []
Jenkins.instance.getAllItems(Job).each { job ->
  job.triggers.each { key, trigger ->
    if (trigger instanceof TimerTrigger) {
      disabled << "${job.fullName}: ${trigger.spec}"
      job.removeTrigger(trigger.descriptor)
    }
  }
}
if (disabled) {
  println "Disabled ${disabled.size()} cron triggers:"
  disabled.each { println "  - ${it}" }
} else {
  println "No cron triggers found"
}

// Self-delete
new File("/var/jenkins_home/init.groovy.d/disable-crons.groovy").delete()
