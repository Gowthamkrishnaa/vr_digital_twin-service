output "neptune_security_group_id" {
  description = "Security Group ID for Neptune"
  value       = aws_security_group.neptune_sg.id
}

output "neptune_subnet_group_name" {
  description = "Subnet Group name for Neptune"
  value       = aws_neptune_subnet_group.neptune_subnet_group.name
}

output "neptune_cluster_identifier" {
  description = "Identifier of the Neptune cluster"
  value       = aws_neptune_cluster.neptune_cluster.id
}

output "neptune_cluster_endpoint" {
  description = "Endpoint of the Neptune cluster"
  value       = aws_neptune_cluster.neptune_cluster.endpoint
}
