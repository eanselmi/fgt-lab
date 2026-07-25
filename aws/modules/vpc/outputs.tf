output "vpc_id" {
  description = "ID del VPC."
  value       = aws_vpc.this.id
}

output "igw_id" {
  description = "ID del Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas."
  value       = aws_subnet.private[*].id
}
