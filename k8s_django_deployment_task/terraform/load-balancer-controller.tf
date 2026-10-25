resource "aws_iam_role" "load_balancer_controller" {
  name = "${local.project_name}-lbc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
            "aws:RequestTag/kubernetes-service-account" = "aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${local.project_name}-lbc"
  description = "Permissions for AWS Load Balancer Controller"

  policy = file(
    "${path.module}/policies/aws-load-balancer-controller.json"
  )
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.load_balancer_controller.arn

  depends_on = [
    aws_iam_role_policy_attachment.load_balancer_controller
  ]
}
