# Configure the CloudStack Provider
# Will use CLOUDSTACK_API_KEY and CLOUDSTACK_SECRET_KEY env vars
provider "cloudstack" {
  api_url = "https://api.exoscale.ch/compute"
}

resource "cloudstack_ssh_keypair" "default" {
  name       = "SSH key"
  public_key = "${file("cloudstack_id_rsa.pub")}"
}

resource "cloudstack_security_group" "web" {
  name        = "web"
  description = "Web Servers"
}

resource "cloudstack_security_group_rule" "web" {
  security_group_id = "${cloudstack_security_group.web.id}"

  # Allow HTTP, HTTPS and SSH traffic from entire Internet
  rule {
    cidr_list = [
      "0.0.0.0/0",
    ]

    ports = [
      80,
      443,
      22,
    ]

    protocol     = "tcp"
    traffic_type = "ingress"
  }
}

resource "cloudstack_instance" "web" {
  template         = "Linux CentOS 7.2 64-bit"
  service_offering = "Micro"
  zone             = "ch-gva-2"
  root_disk_size   = "50"
  expunge          = true
  keypair          = "${cloudstack_ssh_keypair.default.id}"

  security_group_ids = [
    "${cloudstack_security_group.web.id}",
  ]
}
