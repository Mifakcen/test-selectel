terraform {
  required_providers {
    selectel = {
      source = "selectel/selectel"
      version = "5.1.1"
    }
    openstack = {
      source = "terraform-provider-openstack/openstack"
      version = "2.1.0"
    }
  }
}

provider "selectel" {
  domain_name = ""
  username    = "admin_test"
  password    = ""
}

resource "selectel_vpc_project_v2" "project_1" {
  name = "project_test_nginx"
}

resource "selectel_iam_serviceuser_v1" "serviceuser_1" {
  name     = ""
  password = ""

  role {
    role_name  = "member"
    scope      = "project"
    project_id = selectel_vpc_project_v2.project_1.id
  }
}

provider "openstack" {
  auth_url    = "https://cloud.api.selcloud.ru/identity/v3"
  domain_name = "335286"
  tenant_id   = selectel_vpc_project_v2.project_1.id
  user_name   = selectel_iam_serviceuser_v1.serviceuser_1.name
  password    = selectel_iam_serviceuser_v1.serviceuser_1.password
  region      = "ru-9"
}

resource "selectel_vpc_keypair_v2" "keypair_1" {
  name       = "keypair"
  public_key = file("~/.ssh/id_rsa.pub")
  user_id    = selectel_iam_serviceuser_v1.serviceuser_1.id
}

resource "openstack_compute_flavor_v2" "flavor_1" {
  name      = "nginx-flavor"
  vcpus     = 1
  ram       = 512
  disk      = 0
  is_public = false

  lifecycle {
    create_before_destroy = true
  }
}

resource "openstack_networking_network_v2" "network_1" {
  name           = "private-network"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "subnet_1" {
  name       = "private-subnet"
  network_id = openstack_networking_network_v2.network_1.id
  cidr       = "192.168.199.0/24"
}

data "openstack_networking_network_v2" "external_network_1" {
  external = true
}

resource "openstack_networking_router_v2" "router_1" {
  name                = "router"
  external_network_id = data.openstack_networking_network_v2.external_network_1.id
}

resource "openstack_networking_router_interface_v2" "router_interface_1" {
  router_id = openstack_networking_router_v2.router_1.id
  subnet_id = openstack_networking_subnet_v2.subnet_1.id
}

resource "openstack_networking_port_v2" "port_1" {
  name       = "port"
  network_id = openstack_networking_network_v2.network_1.id

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet_1.id
  }
}

data "openstack_images_image_v2" "image_1" {
  name        = "Ubuntu 24.04 LTS 64-bit"
  most_recent = true
  visibility  = "public"
}

resource "openstack_blockstorage_volume_v3" "volume_1" {
  name                = "boot-volume-for-server"
  size                = 5
  image_id            = data.openstack_images_image_v2.image_1.id
  volume_type         = "fast.ru-9a"
  availability_zone   = "ru-9a"
  enable_online_resize = true

  lifecycle {
    ignore_changes = [image_id]
  }
}

resource "openstack_compute_instance_v2" "server_1" {
  name              = "test_nginx"
  flavor_id         = openstack_compute_flavor_v2.flavor_1.id
  key_pair          = selectel_vpc_keypair_v2.keypair_1.name
  availability_zone = "ru-9a"

  network {
    port = openstack_networking_port_v2.port_1.id
  }

  block_device {
    uuid            = openstack_blockstorage_volume_v3.volume_1.id
    source_type     = "volume"
    destination_type = "volume"
    boot_index      = 0
  }

  vendor_options {
    ignore_resize_confirmation = true
  }

  provisioner "file" {
    source      = "~/port_open.sh"
    destination = "/root/port_open.sh"
    connection {
      type        = "ssh"
      user        = "root"
      private_key = file("~/.ssh/id_rsa")
      host        = openstack_networking_floatingip_v2.floatingip_1.address
    }

  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /root/port_open.sh",
      "/root/port_open.sh"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file("~/.ssh/id_rsa")
      host        = openstack_networking_floatingip_v2.floatingip_1.address
    }
  }

  depends_on = [openstack_networking_floatingip_associate_v2.association_1]
}

resource "openstack_networking_floatingip_v2" "floatingip_1" {
  pool = data.openstack_networking_network_v2.external_network_1.name
}
resource "openstack_networking_floatingip_associate_v2" "association_1" {
  port_id     = openstack_networking_port_v2.port_1.id
  floating_ip = openstack_networking_floatingip_v2.floatingip_1.address
}

output "public_ip_address" {
  value = openstack_networking_floatingip_v2.floatingip_1.address
}
