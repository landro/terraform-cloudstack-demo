# Configure the CloudStack Provider
# Will use CLOUDSTACK_API_KEY and CLOUDSTACK_SECRET_KEY env vars
provider "cloudstack" {
  api_url = "https://api.exoscale.ch/compute"
}

resource "cloudstack_ssh_keypair" "default" {
  name       = "SSH key"
  public_key = "${file("yubikey_id_rsa.pub")}"
}

resource "cloudstack_security_group" "web" {
  name        = "web"
  description = "Web Servers"
}

resource "cloudstack_security_group_rule" "web" {
  security_group_id = "${cloudstack_security_group.web.id}"

  # Allow HTTP and HTTPS traffic from entire Internet
  rule {
    cidr_list = [
      "0.0.0.0/0",
    ]

    ports = [
      80,
      443,
    ]

    protocol     = "tcp"
    traffic_type = "ingress"
  }

  # Allow management connections from bastion
  rule {
    user_security_group_list = [
      "${cloudstack_security_group.bastion.name}",
    ]

    ports = [
      22,
    ]

    protocol     = "tcp"
    traffic_type = "ingress"
  }
}

variable "zone" {
  description = "Cloudstack Availability Zone"
  type        = "string"

  #default = "ch-dk-2"
  default = "ch-gva-2"
}

variable "nb_web_servers" {
  type        = "string"
  description = "Number of web servers"
  default     = "2"
}

resource "cloudstack_instance" "web" {
  display_name     = "web${count.index}"
  count            = "${var.nb_web_servers}"
  name             = ""
  template         = "Linux CentOS 7.2 64-bit"
  service_offering = "Micro"
  zone             = "${var.zone}"
  root_disk_size   = "50"
  expunge          = true
  keypair          = "${cloudstack_ssh_keypair.default.id}"

  affinity_group_ids = [
    "${cloudstack_affinity_group.web.id}",
  ]

  security_group_ids = [
    "${cloudstack_security_group.web.id}",
  ]

  # Install and run Apache httpd right after
  # provisioning instance
  provisioner "remote-exec" {
    inline = [
      "yum -y install httpd",
      "yum -y install mod_ssl",
      "systemctl start httpd",
    ]
  }

  # Connect through bastion host
  connection {
    type         = "ssh"
    user         = "root"
    bastion_host = "${cloudstack_instance.bastion.ip_address}"
    agent        = true
  }
}

# Make sure web servers don't run on same host
resource "cloudstack_affinity_group" "web" {
  name = "web-affinity-group"
  type = "host anti-affinity"
}

resource "cloudstack_security_group" "bastion" {
  name        = "bastion"
  description = "Bastion Servers"
}

resource "cloudstack_security_group_rule" "bastion" {
  security_group_id = "${cloudstack_security_group.bastion.id}"

  # Allow management connection
  # from well known IP range
  rule {
    protocol = "tcp"

    ports = [
      22,
    ]

    traffic_type = "ingress"

    cidr_list = [
      # Replace this with your IP address
      "0.0.0.0/0",
    ]
  }

  # Allow management connection to web servers through bastion
  rule {
    protocol = "tcp"

    ports = [
      22,
    ]

    traffic_type = "egress"

    user_security_group_list = [
      "${cloudstack_security_group.web.name}",
    ]
  }
}

resource "cloudstack_instance" "bastion" {
  display_name     = "bastion"
  template         = "Linux CentOS 7.2 64-bit"
  service_offering = "Micro"
  expunge          = true
  zone             = "${var.zone}"
  root_disk_size   = "50"
  keypair          = "${cloudstack_ssh_keypair.default.id}"

  security_group_ids = [
    "${cloudstack_security_group.bastion.id}",
  ]
}

output "Bastion IP" {
  value = "${cloudstack_instance.bastion.ip_address}"
}

output "Web IPs" {
  value = "${join(", ",cloudstack_instance.web.*.ip_address)}"
}

# Configure the AWS Provider
# Will use AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
provider "aws" {
  region = "eu-central-1"
}

# Looked up manually in aws route 53 console
# Consider using aws_route53_zone resource instead
variable "dns_zone_id" {
  default     = "Z2X1UBSEPFNQNM"
  description = "DNS hosted zone id"
  type        = "string"
}

# Create DNS records for exoscale web servers
resource "aws_route53_record" "exoscale" {
  zone_id = "${var.dns_zone_id}"
  name    = "exoscale.landro.io."
  type    = "A"
  ttl     = 60

  records = [
    "${cloudstack_instance.web.*.ip_address}",
  ]
}

# Configure the Arukas Provider
# Will use ARUKAS_JSON_API_TOKEN and ARUKAS_JSON_API_SECRET
provider "arukas" {}

resource "arukas_container" "arukas" {
  name      = "Arukas"
  image     = "landro/httpd-centos-alpine:latest"
  instances = 1
  memory    = 256

  ports = {
    protocol = "tcp"
    number   = "80"
  }
}

# Create DNS CNAME record for exoscale vms
# in order to support DNS routing
resource "aws_route53_record" "cloudstack" {
  zone_id = "${var.dns_zone_id}"
  name    = "cloudstack.landro.io."
  type    = "CNAME"
  ttl     = 60

  records = [
    "${aws_route53_record.exoscale.fqdn}",
  ]
}

# Create DNS CNAME record for arukas containers
# in order to support DNS routing
resource "aws_route53_record" "arukas" {
  zone_id = "${var.dns_zone_id}"
  name    = "arukas.landro.io."
  type    = "CNAME"
  ttl     = 60

  records = [
    "${arukas_container.arukas.endpoint_full_hostname}",
  ]
}

# Create DNS record with weighted routing policy and health checking
# targeting cloudstack
resource "aws_route53_record" "cloudstack_www" {
  zone_id = "${var.dns_zone_id}"
  name    = "www.landro.io."
  type    = "CNAME"

  weighted_routing_policy {
    weight = "${var.nb_web_servers}"
  }

  set_identifier = "cloustack"

  alias {
    name                   = "${aws_route53_record.cloudstack.fqdn}"
    zone_id                = "${aws_route53_record.cloudstack.zone_id}"
    evaluate_target_health = true
  }

  health_check_id = "${aws_route53_health_check.cloudstack.id}"
}

# Create DNS record with weighted routing policy and health checking
# targeting arukas
resource "aws_route53_record" "arukas_www" {
  zone_id = "${var.dns_zone_id}"
  name    = "www.landro.io."
  type    = "CNAME"

  weighted_routing_policy {
    weight = "${arukas_container.arukas.instances}"
  }

  set_identifier = "arukas"

  alias {
    name                   = "${aws_route53_record.arukas.fqdn}"
    zone_id                = "${aws_route53_record.arukas.zone_id}"
    evaluate_target_health = true
  }

  health_check_id = "${aws_route53_health_check.arukas.id}"
}

# Create health check targeting Apache httpd on centos
resource "aws_route53_health_check" "cloudstack" {
  fqdn              = "${aws_route53_record.cloudstack.fqdn}"
  port              = 80
  type              = "HTTP"
  resource_path     = "/images/poweredby.png"
  failure_threshold = "3"
  request_interval  = "10"
}

# Create health check targeting Apache httpd on alpine
resource "aws_route53_health_check" "arukas" {
  fqdn              = "${arukas_container.arukas.endpoint_full_hostname}"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = "3"
  request_interval  = "10"
}
