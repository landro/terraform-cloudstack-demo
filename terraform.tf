# Configure the CloudStack Provider
# Will use CLOUDSTACK_API_KEY and CLOUDSTACK_SECRET_KEY env vars
provider "cloudstack" {
  api_url = "https://api.exoscale.ch/compute"
}

resource "cloudstack_ssh_keypair" "default" {
  name       = "SSH key"
  public_key = "${file("cloudstack_id_rsa.pub")}"
}
