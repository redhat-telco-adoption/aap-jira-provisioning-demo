output "zabbix_public_ip" {
  value = aws_instance.zabbix_server.public_ip
}

output "zabbix_private_ip" {
  value = aws_instance.zabbix_server.private_ip
}

output "rds_address" {
  value = aws_db_instance.shared_postgres.address
}

output "ssh_key_path" {
  value       = local_sensitive_file.private_key.filename
  description = "Path to the generated SSH private key"
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value       = aws_subnet.public_a.id
  description = "Subnet used for ticket-provisioned demo VMs"
}

output "demo_vm_sg_id" {
  value       = aws_security_group.demo_vm.id
  description = "Security group attached to ticket-provisioned demo VMs"
}

output "key_pair_name" {
  value = aws_key_pair.demo.key_name
}

output "summary" {
  value = <<-EOT
    Zabbix Web:      http://${aws_instance.zabbix_server.public_ip}
    Zabbix private:  ${aws_instance.zabbix_server.private_ip}
    RDS Endpoint:    ${aws_db_instance.shared_postgres.address}
    Demo VM subnet:  ${aws_subnet.public_a.id}
    Demo VM SG:      ${aws_security_group.demo_vm.id}
    Key pair:        ${aws_key_pair.demo.key_name} (${local_sensitive_file.private_key.filename})
  EOT
}
