resource "aws_security_group" "database" {
  name        = "${local.project_name}-database"
  description = "PostgreSQL access from EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${local.project_name}-database"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_eks" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = module.eks.node_security_group_id

  description = "PostgreSQL from EKS worker nodes"
  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
}

resource "aws_db_instance" "application" {
  identifier = local.project_name

  engine                   = "postgres"
  engine_version           = "17.11"
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  instance_class           = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 0
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = "hc"
  username                    = "hc_admin"
  manage_master_user_password = true
  port                        = 5432

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 0
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.project_name}-final"

  tags = {
    Name = local.project_name
  }

  depends_on = [
    aws_vpc_security_group_ingress_rule.postgres_from_eks
  ]
}

output "rds_address" {
  description = "Private PostgreSQL hostname"
  value       = aws_db_instance.application.address
}

output "rds_port" {
  description = "PostgreSQL port"
  value       = aws_db_instance.application.port
}

output "rds_master_secret_arn" {
  description = "ARN of the RDS-managed administrative credentials secret"
  value       = aws_db_instance.application.master_user_secret[0].secret_arn
}
