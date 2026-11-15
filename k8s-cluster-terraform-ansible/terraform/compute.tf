variable "admin_cidr" {
  type        = string
  description = "Public IPv4 CIDR of the laptop, with a /32 prefix."

  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Set admin_cidr to one public IPv4 address with a /32 prefix."
  }
}

variable "lab_ssh_key_path" {
  type        = string
  description = "Path on the laptop to the lab SSH key. Terraform reads only the .pub file."
  default     = "~/.ssh/week10-k8s-lab"
}

locals {
  nodes = {
    control-plane = { group = "control_plane", host_number = 10 }
    worker-1      = { group = "workers", host_number = 21 }
    worker-2      = { group = "workers", host_number = 22 }
  }
}

data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
}

resource "aws_key_pair" "lab" {
  key_name   = "week10-k8s-lab"
  public_key = file("${pathexpand(var.lab_ssh_key_path)}.pub")
}

resource "aws_instance" "node" {
  for_each = local.nodes

  ami                         = data.aws_ami.ubuntu_arm64.id
  instance_type               = "t4g.small"
  subnet_id                   = aws_subnet.public.id
  private_ip                  = cidrhost(aws_subnet.public.cidr_block, each.value.host_number)
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.cluster[each.value.group].id]
  key_name                    = aws_key_pair.lab.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "week10-${each.key}"
  }

  depends_on = [aws_route_table_association.public]
}
