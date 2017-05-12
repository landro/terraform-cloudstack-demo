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
}

# Make sure web servers don't run on same host
resource "cloudstack_affinity_group" "web" {
  name = "web-affinity-group"
  type = "host anti-affinity"
}
