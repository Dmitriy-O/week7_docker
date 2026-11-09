locals {
  kubernetes_user_groups = {
    viewer   = "healthchecks-viewers"
    operator = "healthchecks-operators"
  }
}

resource "aws_iam_role" "kubernetes_user" {
  for_each = local.kubernetes_user_groups

  name        = "${local.project_name}-${each.key}"
  description = "EKS identity for namespace-scoped Kubernetes RBAC"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        AWS = "arn:aws:iam::047472448571:user/terraform_lab_user"
      }
    }]
  })
}

resource "aws_eks_access_entry" "kubernetes_user" {
  for_each = local.kubernetes_user_groups

  cluster_name      = module.eks.cluster_name
  principal_arn     = aws_iam_role.kubernetes_user[each.key].arn
  kubernetes_groups = [each.value]
  type              = "STANDARD"
}

output "kubernetes_user_role_arns" {
  value = {
    for name, role in aws_iam_role.kubernetes_user : name => role.arn
  }
}
