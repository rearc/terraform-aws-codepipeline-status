variable "github_app_private_key" {
  type        = string
  description = "Name of GitHub App private key in Parameter Store, e.g. github-status-key"
  default     = ""
}

variable "github_app_id" {
  type        = string
  description = "ID of GitHub App, e.g. 63948"  
  default     = ""  
}

variable "github_app_install_id" {
  type        = string
  description = "ID of GitHub App installation, e.g. 8698893"
  default     = ""
}

variable "github_personal_access_token" {
  type        = string
  description = "Name of GitHub personal access token in Parameter Store, e.g. mwkaufman-token"
  default     = ""
}

