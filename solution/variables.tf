variable "environment" {
  description = "The environment label used in names and tags."
  type        = string
}

variable "location" {
  description = "The Azure region for the workshop resources."
  type        = string
  default     = "westeurope"
}

variable "vm_size" {
  description = "The VM size; availability depends on the sandbox subscription and region."
  type        = string
  default     = "Standard_B1s"
}
