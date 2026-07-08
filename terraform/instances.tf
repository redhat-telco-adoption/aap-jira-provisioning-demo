# Only the Zabbix server is managed by Terraform.
# Demo VMs are created per-ticket by the AAP job template
# (ansible/playbooks/vm_request_fulfillment.yml), tagged Demo=aap-jira-demo.

resource "aws_instance" "zabbix_server" {
  ami                    = var.zabbix_ami
  instance_type          = var.zabbix_instance_type
  key_name               = aws_key_pair.demo.key_name
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.zabbix.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.zabbix_disk_size
    encrypted   = true
  }

  tags = {
    Name        = "${var.project_name}-zabbix-server"
    Role        = "zabbix_server"
    Project     = var.project_name
    Environment = var.environment
  }
}
