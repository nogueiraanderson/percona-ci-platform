plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Skeleton phase: variables and locals are pre-staged for modules that will be
# wired in subsequent commits. Re-enable once vpc.tf / eks.tf / etc. are
# uncommented.
rule "terraform_unused_declarations" {
  enabled = false
}
