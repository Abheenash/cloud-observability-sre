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

variable "api_name" {
  type    = string
  default = "sfs-api"
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
