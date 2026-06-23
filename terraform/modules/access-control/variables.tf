variable "name_prefix" {
  type = string
}

variable "admin_user_emails" {
  description = "Email addresses to add to the workspace admins group."
  type        = list(string)
  default     = []
}

variable "sandbox_user_emails" {
  description = "Email addresses to add to the sandbox-users group (restricted access)."
  type        = list(string)
  default     = []
}
