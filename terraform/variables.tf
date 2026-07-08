# --- Network ---
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
variable "public_subnet_a_cidr" {
  default = "10.0.1.0/24"
}
variable "public_subnet_b_cidr" {
  default = "10.0.2.0/24"
}

# --- Compute ---
variable "zabbix_ami" {
  description = "RHEL 9 AMI for the Zabbix server"
}
variable "zabbix_instance_type" {
  default = "t3.medium"
}
variable "zabbix_disk_size" {
  default = 20
}

# --- SSH key pair ---
variable "key_pair_name" {
  description = "Name of the generated EC2 key pair (private key written to ../keys/<name>.pem)"
  default     = "demo-key"
}

# --- RDS ---
variable "rds_instance_class" {
  default = "db.m5.large"
}
variable "rds_engine_version" {
  default = "15"
}
variable "rds_allocated_storage" {
  default = 50
}
variable "rds_master_username" {
  default = "postgres"
}
variable "rds_master_password" {
  sensitive = true
}

# --- Tags ---
variable "project_name" {
  default = "aap-jira-demo"
}
variable "environment" {
  default = "demo"
}

variable "base_domain" {
  description = "Route53 hosted zone for stable DNS (e.g. sandboxNNNN.opentlc.com)"
  type        = string
}
