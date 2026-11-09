output "rds_bootstrap_secret_read_policy" {
  description = "Scoped bootstrap policy for an authorized AWS administrator to grant to terraform_lab_user."

  value = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadCurrentRDSBootstrapCredentials"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_db_instance.application.master_user_secret[0].secret_arn
    }]
  })
}
