variable "project"                     { type = string }
variable "environment"                 { type = string }
variable "ami_id"                      { type = string }
variable "control_plane_instance_type" { type = string }
variable "worker_instance_type"        { type = string }
variable "worker_count"                { type = number }
variable "subnet_id"                   { type = string }
variable "security_group_id"           { type = string }
variable "ssh_public_key"              { type = string }

resource "aws_key_pair" "nodes" {
  key_name   = "${var.project}-${var.environment}-key"
  public_key = var.ssh_public_key
}

# ── Control plane ─────────────────────────────────────────────────────────────
resource "aws_instance" "control_plane" {
  ami                    = var.ami_id
  instance_type          = var.control_plane_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.nodes.key_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-control-plane"
    Role = "control-plane"
  }
}

# ── Workers ───────────────────────────────────────────────────────────────────
resource "aws_instance" "workers" {
  count = var.worker_count

  ami                    = var.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.nodes.key_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-worker-${count.index + 1}"
    Role = "worker"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "control_plane_public_ip"  { value = aws_instance.control_plane.public_ip }
output "control_plane_private_ip" { value = aws_instance.control_plane.private_ip }
output "worker_public_ips"        { value = aws_instance.workers[*].public_ip }
output "worker_private_ips"       { value = aws_instance.workers[*].private_ip }
