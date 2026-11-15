output "vpc_id" {
  description = "ID of the Kubernetes lab VPC"
  value       = aws_vpc.lab.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}
