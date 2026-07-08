# Stable addressing for the Zabbix server: an Elastic IP (survives instance
# stop/start) plus a Route53 record in the sandbox hosted zone.

data "aws_route53_zone" "base" {
  name         = var.base_domain
  private_zone = false
}

resource "aws_eip" "zabbix" {
  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-zabbix-eip"
    Project = var.project_name
  }
}

resource "aws_eip_association" "zabbix" {
  instance_id   = aws_instance.zabbix_server.id
  allocation_id = aws_eip.zabbix.id
}

resource "aws_route53_record" "zabbix" {
  zone_id = data.aws_route53_zone.base.zone_id
  name    = "zabbix.${var.base_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.zabbix.public_ip]
}
