variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "phoenix"
}

variable "environment" {
  description = "Environment tag (e.g. prod, staging)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the k3s control plane"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_type" {
  description = "EC2 instance type for k3s workers"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID (region-specific — set in tfvars)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key material to install on nodes"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your public IP in CIDR notation for SSH access (e.g. 1.2.3.4/32)"
  type        = string
}

variable "s3_state_bucket" {
  description = "S3 bucket name for Terraform remote state"
  type        = string
}

variable "dynamodb_lock_table" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "phoenix-tf-locks"
}
