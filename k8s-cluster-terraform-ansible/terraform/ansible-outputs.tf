locals {
  cluster_artifacts_dir = abspath("${path.root}/../artifacts/cluster")
  control_plane         = aws_instance.node["control-plane"]
  workers = {
    for name, node in aws_instance.node : name => node
    if local.nodes[name].group == "workers"
  }
}

output "ansible_inventory" {
  description = "Ansible inventory for the three EC2 instances."
  value = {
    all = {
      vars = {
        ansible_user                 = "ubuntu"
        ansible_ssh_private_key_file = abspath(pathexpand(var.lab_ssh_key_path))
      }
      children = {
        control_plane = {
          hosts = {
            control-plane = {
              ansible_host             = local.control_plane.public_ip
              control_plane_private_ip = local.control_plane.private_ip
            }
          }
        }
        workers = {
          hosts = {
            for name, node in local.workers : name => {
              ansible_host = node.public_ip
              node_ip      = node.private_ip
            }
          }
        }
      }
    }
  }
}

output "ansible_pki_vars" {
  description = "Variables for preparing the real cluster PKI."
  value = {
    pki_output_dir            = local.cluster_artifacts_dir
    pki_dir                   = "${local.cluster_artifacts_dir}/pki"
    ca_common_name            = "week10-cluster-ca"
    pki_api_endpoint_external = "https://${local.control_plane.public_ip}:6443"
    pki_api_endpoint_internal = "https://${local.control_plane.private_ip}:6443"
    pki_api_sans = [
      "IP:${local.control_plane.public_ip}",
      "IP:${local.control_plane.private_ip}",
      "IP:10.96.0.1",
      "DNS:kubernetes",
      "DNS:kubernetes.default",
      "DNS:kubernetes.default.svc",
      "DNS:kubernetes.default.svc.cluster.local",
    ]
    pki_workers = [
      for name, node in local.workers : { name = name, ip = node.private_ip }
    ]
  }
}
