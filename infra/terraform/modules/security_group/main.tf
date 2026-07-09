variable "project"          { type = string }
variable "environment"      { type = string }
variable "vpc_id"           { type = string }
variable "vpc_cidr"         { type = string }
variable "allowed_ssh_cidr" { type = string }

resource "aws_security_group" "nodes" {
  name        = "${var.project}-${var.environment}-nodes"
  description = "k3s cluster nodes - least-privilege"
  vpc_id      = var.vpc_id

  # ── Inbound: world-accessible ─────────────────────────────────────────────

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from your IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # ── Inbound: intra-cluster only (NOT open to 0.0.0.0/0) ──────────────────

  ingress {
    description = "k3s API server - cluster-internal only"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Flannel VXLAN (node-to-node)"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "kubelet metrics (node-to-node)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "NodePort range (internal LB probes only)"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ── Outbound: unrestricted ────────────────────────────────────────────────

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-nodes-sg" }
}

output "node_sg_id" { value = aws_security_group.nodes.id }
