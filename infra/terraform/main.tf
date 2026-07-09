terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Values come from -backend-config flags or partial config file.
    # Example:
    #   terraform init \
    #     -backend-config="bucket=my-phoenix-tfstate" \
    #     -backend-config="key=capstone/phoenix.tfstate" \
    #     -backend-config="region=eu-west-1" \
    #     -backend-config="dynamodb_table=phoenix-tf-locks"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── Network ──────────────────────────────────────────────────────────────────
module "network" {
  source      = "./modules/network"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  subnet_cidr = var.subnet_cidr
  aws_region  = var.aws_region
}

# ── Security groups ───────────────────────────────────────────────────────────
module "security_group" {
  source           = "./modules/security_group"
  project          = var.project
  environment      = var.environment
  vpc_id           = module.network.vpc_id
  vpc_cidr         = var.vpc_cidr
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

# ── Compute ───────────────────────────────────────────────────────────────────
module "compute" {
  source                      = "./modules/compute"
  project                     = var.project
  environment                 = var.environment
  ami_id                      = var.ami_id
  control_plane_instance_type = var.control_plane_instance_type
  worker_instance_type        = var.worker_instance_type
  worker_count                = var.worker_count
  subnet_id                   = module.network.subnet_id
  security_group_id           = module.security_group.node_sg_id
  ssh_public_key              = var.ssh_public_key
}
