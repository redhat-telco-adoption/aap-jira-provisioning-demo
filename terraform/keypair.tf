resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "demo" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.demo.public_key_openssh

  tags = {
    Name        = var.key_pair_name
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_pem
  filename        = abspath("${path.module}/../keys/${var.key_pair_name}.pem")
  file_permission = "0600"
}
