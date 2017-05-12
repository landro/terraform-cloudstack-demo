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
