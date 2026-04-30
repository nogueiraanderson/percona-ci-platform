variable "aws_region" {
  description = "AWS region for the EKS cluster + all data-plane resources."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = <<-EOT
    Optional AWS named profile. Leave empty to use the SDK default credential
    chain (env vars, EC2 instance profile, SSO, etc.). This var exists so
    contributors can override locally without editing the providers block.
  EOT
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "EKS cluster name. Matches the repo name."
  type        = string
  default     = "percona-ci-platform"
}

variable "cluster_version" {
  description = <<-EOT
    EKS Kubernetes minor version. Track standard support only — picking a version
    in extended support incurs the paid extended-support fee (CLAUDE.md rule).
    Verify with `aws eks describe-cluster-versions`.
  EOT
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "Cluster VPC CIDR. Avoid the Jenkins-VPC ranges 10.144/.155/.166/.177/.179/.188/.199 (multi-region masters)."
  type        = string
  default     = "10.220.0.0/16"
}

variable "argocd_hostname" {
  description = "Public hostname for ArgoCD UI. external-dns publishes the ALB alias."
  type        = string
  default     = "argocd.cd.percona.com"
}

variable "grafana_hostname" {
  description = "Public hostname for Grafana UI."
  type        = string
  default     = "grafana.cd.percona.com"
}

variable "route53_zone_name" {
  description = "Public hosted zone for *.cd.percona.com (Z1H0AFAU7N8IMC)."
  type        = string
  default     = "cd.percona.com"
}

variable "monitoring_az" {
  description = "Single AZ for stateful workloads (Prometheus, Jenkins masters). EBS is zonal."
  type        = string
  default     = "us-east-1a"
}

variable "jenkins_hosts" {
  description = <<-EOT
    Jenkins masters governed by this platform. mode = in-cluster (StatefulSet) or
    proxy (NGINX Deployment reverse-proxying to a per-host origin EC2 master).
    Add a host's mode = in-cluster after migration; before, keep it as proxy.
  EOT
  type = map(object({
    mode             = string # "in-cluster" or "proxy"
    upstream_origin  = optional(string)
    upstream_az      = optional(string)
    storage_size_gib = optional(number)
  }))
  default = {
    ps3 = {
      mode             = "in-cluster"
      upstream_origin  = "origin-ps3.cd.percona.com"
      upstream_az      = "us-east-1a"
      storage_size_gib = 100
    }
    pmm   = { mode = "proxy", upstream_origin = "origin-pmm.cd.percona.com" }
    ps80  = { mode = "proxy", upstream_origin = "origin-ps80.cd.percona.com" }
    pxc   = { mode = "proxy", upstream_origin = "origin-pxc.cd.percona.com" }
    pxb   = { mode = "proxy", upstream_origin = "origin-pxb.cd.percona.com" }
    psmdb = { mode = "proxy", upstream_origin = "origin-psmdb.cd.percona.com" }
    pg    = { mode = "proxy", upstream_origin = "origin-pg.cd.percona.com" }
    ps57  = { mode = "proxy", upstream_origin = "origin-ps57.cd.percona.com" }
    rel   = { mode = "proxy", upstream_origin = "origin-rel.cd.percona.com" }
    cloud = { mode = "proxy", upstream_origin = "origin-cloud.cd.percona.com" }
  }
}

variable "tags" {
  description = "Default tags for every taggable AWS resource."
  type        = map(string)
  default = {
    "iit-billing-tag" = "percona-ci-platform"
    "managed-by"      = "opentofu"
    "repo"            = "github.com/nogueiraanderson/percona-ci-platform"
  }
}
