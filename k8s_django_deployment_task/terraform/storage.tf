resource "aws_efs_file_system" "static" {
  creation_token   = "${local.project_name}-static"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "${local.project_name}-static"
  }
}

resource "aws_security_group" "efs_static" {
  name_prefix = "${local.project_name}-efs-"
  description = "NFS access from EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "NFS from worker nodes"
    protocol        = "tcp"
    from_port       = 2049
    to_port         = 2049
    security_groups = [module.eks.node_security_group_id]
  }
}

resource "aws_efs_mount_target" "static" {
  count = length(local.availability_zones)

  file_system_id  = aws_efs_file_system.static.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs_static.id]
}

resource "aws_efs_access_point" "static" {
  file_system_id = aws_efs_file_system.static.id

  posix_user {
    uid = 10001
    gid = 10001
  }

  root_directory {
    path = "/healthchecks-static"

    creation_info {
      owner_uid   = 10001
      owner_gid   = 10001
      permissions = "750"
    }
  }

  tags = {
    Name = "${local.project_name}-static"
  }
}

resource "aws_iam_role" "efs_csi" {
  name = "${local.project_name}-efs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-name"           = local.project_name
          "aws:RequestTag/kubernetes-namespace"       = "kube-system"
          "aws:RequestTag/kubernetes-service-account" = "efs-csi-controller-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

data "aws_eks_addon_version" "efs_csi" {
  addon_name         = "aws-efs-csi-driver"
  kubernetes_version = module.eks.cluster_version
  most_recent        = false
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "aws-efs-csi-driver"
  addon_version = data.aws_eks_addon_version.efs_csi.version

  pod_identity_association {
    service_account = "efs-csi-controller-sa"
    role_arn        = aws_iam_role.efs_csi.arn
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.efs_csi
  ]
}

output "efs_static_volume_handle" {
  value = "${aws_efs_file_system.static.id}::${aws_efs_access_point.static.id}"
}
