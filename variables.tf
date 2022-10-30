# ---autoscaling/variables.tf ---
variable "public_cidrs" {
  type = list(any)
}

variable "public_sn_count" {
  type = number
}

variable "private_sn_count" {
  type = number
}

variable "max_subnets" {
  type = number
}
