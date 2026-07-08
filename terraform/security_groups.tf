resource "aws_security_group" "zabbix" {
  name        = "${var.project_name}-zabbix"
  description = "Security group for Zabbix server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Zabbix web UI HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Zabbix trapper / agent active checks (VPC only)"
    from_port   = 10051
    to_port     = 10051
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg-zabbix"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Attached by Ansible to the per-ticket demo VMs (not managed instances here)
resource "aws_security_group" "demo_vm" {
  name        = "${var.project_name}-demo-vm"
  description = "Security group for ticket-provisioned demo VMs"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg-demo-vm"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "demo_vm_zabbix_agent_poll" {
  type                     = "ingress"
  description              = "Zabbix agent passive checks from the Zabbix server"
  from_port                = 10050
  to_port                  = 10050
  protocol                 = "tcp"
  security_group_id        = aws_security_group.demo_vm.id
  source_security_group_id = aws_security_group.zabbix.id
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Zabbix"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.zabbix.id]
  }

  tags = {
    Name        = "${var.project_name}-sg-rds"
    Project     = var.project_name
    Environment = var.environment
  }
}
