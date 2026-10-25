variable "eks_admin_cidr" {
  description = "Public IPv4 address allowed to access the Kubernetes API"
  type        = string

  validation {
    condition = (
      can(cidrnetmask(var.eks_admin_cidr)) &&
      endswith(var.eks_admin_cidr, "/32")
    )
    error_message = "eks_admin_cidr must be a valid IPv4 CIDR ending in /32."
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = local.project_name
  kubernetes_version = "1.36"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.eks_admin_cidr]

  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  cloudwatch_log_group_retention_in_days = 7

  addons = {
    vpc-cni = {
      before_compute = true
    }

    eks-pod-identity-agent = {
      before_compute = true
    }

    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    application = {
      name                           = "${local.project_name}-application"
      iam_role_name                  = "${local.project_name}-nodes"
      ami_type                       = "AL2023_ARM_64_STANDARD"
      instance_types = ["t4g.small"]
      capacity_type                  = "ON_DEMAND"
      use_latest_ami_release_version = false

      min_size     = 2
      max_size     = 2
      desired_size = 2

      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"

          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }
}
