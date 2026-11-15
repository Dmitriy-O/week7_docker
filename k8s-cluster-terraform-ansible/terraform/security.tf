resource "aws_security_group" "cluster" {
  for_each = toset(["control_plane", "workers"])

  name        = "week10-${each.key}"
  description = "Kubernetes lab access for ${each.key}"
  vpc_id      = aws_vpc.lab.id
}

resource "aws_vpc_security_group_ingress_rule" "laptop_ssh" {
  for_each = aws_security_group.cluster

  security_group_id = each.value.id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "laptop_api" {
  security_group_id = aws_security_group.cluster["control_plane"].id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "cluster" {
  for_each = {
    workers_to_api   = { source = "workers", target = "control_plane", protocol = "tcp", port = 6443 }
    api_to_kubelet   = { source = "control_plane", target = "workers", protocol = "tcp", port = 10250 }
    workers_to_vxlan = { source = "workers", target = "workers", protocol = "udp", port = 8472 }
  }

  security_group_id            = aws_security_group.cluster[each.value.target].id
  referenced_security_group_id = aws_security_group.cluster[each.value.source].id
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
}

resource "aws_vpc_security_group_egress_rule" "internet" {
  for_each = aws_security_group.cluster

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
