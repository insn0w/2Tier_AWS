# --- root/variables.tf ---
variable "public_cidrs" {
  type    = list(any)
  default = ["10.0.1.0/24", "10.0.3.0/24", "10.0.5.0/24"]
}
