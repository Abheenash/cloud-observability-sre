variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "sfs-obs"
}

# --- the observed service: the live serverless-file-share stack (#1) ---

variable "api_id" {
  description = "HTTP API id of sfs-api."
  type        = string
  default     = "xpvv2dhvnb"
}

variable "lambda_functions" {
  description = "The observed Lambda function names."
  type        = list(string)
  default     = ["sfs-issue-url", "sfs-download", "sfs-reaper"]
}

variable "dynamodb_table" {
  type    = string
  default = "sfs-metadata"
}

variable "uptime_url" {
  description = "Public URL the canary probes for outside-in uptime."
  type        = string
  default     = "https://share.abheenash.com/"
}

variable "alarm_email" {
  description = "Email for SLO/alarm notifications (empty = no subscription)."
  type        = string
  default     = ""
}

# --- web / domain monitoring (RUM + CloudFront) ---

variable "portfolio_domain" {
  type    = string
  default = "abheenash.com"
}

variable "rum_monitor_name" {
  type    = string
  default = "abheenash-portfolio"
}

variable "portfolio_distribution_id" {
  description = "CloudFront distribution serving abheenash.com."
  type        = string
  default     = "E2HDMOM0Q7SCE6"
}

variable "app_distribution_id" {
  description = "CloudFront distribution serving share.abheenash.com."
  type        = string
  default     = "E3KEQ53OO7U9AA"
}

# --- SLO targets ---

variable "slo_availability_pct" {
  description = "Availability SLO target (%). Error budget = 100 - this."
  type        = number
  default     = 99
}

variable "slo_p95_latency_ms" {
  description = "p95 latency SLO for the API (ms)."
  type        = number
  default     = 1500
}

variable "splunk_hec_url" {
  description = <<-EOT
    Splunk HTTP Event Collector endpoint, e.g.
    https://http-inputs-<stack>.splunkcloud.com/services/collector.
    Empty (the default) disables the whole forwarder — there is no Splunk in this
    account, and a forwarder pointing nowhere just fills a DLQ.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.splunk_hec_url == "" || startswith(var.splunk_hec_url, "https://")
    error_message = "The HEC endpoint must be https — the token is a bearer credential."
  }
}

variable "splunk_hec_token" {
  description = "Placeholder only. The real token is set out of band; see splunk.tf."
  type        = string
  default     = "set-me-out-of-band"
  sensitive   = true
}

variable "splunk_index" {
  type    = string
  default = "main"
}

variable "datadog_api_key" {
  description = "Empty (the default) disables every Datadog resource. There is no Datadog org behind this account."
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_app_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "datadog_site" {
  description = "datadoghq.com, datadoghq.eu, ddog-gov.com — the wrong site is a confusing 403."
  type        = string
  default     = "datadoghq.com"
}

variable "datadog_notify" {
  description = "Datadog notification handle, e.g. slack-oncall or an email."
  type        = string
  default     = "abheenash007@gmail.com"
}
