# VPN setup between AWS and Alicloud using Terraform

> ___Note___:
> This is not a guide on the internals of a Virtual Private Network. Rather, this post outlines how to setup a VPN connection between AWS and Alicloud. This guide uses Terraform for making API calls and state management. You can chose to use any HTTP client or aws and alicloud CLIs as well for making the same API calls and end up with a working VPN connection.
Problem Statement
----------------
When you are working in a multicloud environment, many scenarios involve establishing a communication channel between services and resources that lie across cloud providers. For example, you might have a common __Rundeck__ machine that deployes the build binaries onto virtual machines residing in AWS as well as Azure. Another example might be a script in your CI/CD platform that interacts periodically with resources across cloud providers like __RDS__, __Mongo__, __RabbitMQ__, etc., for regularly monitoring or updating different ACL Policies.

![Multi Cloud Architecture](https://www.simform.com/wp-content/uploads/2017/11/Blog-Diagram1.png "Multi Cloud Architecture")

Creating a VPN connection helps you securely access resources on one cloud provider from another over an encrypted connection. A VPN connection helps you avoid the hassle of exposing public endpoints for each resource and then securing it. You can simply go ahead and whietelist a CIDR block across the VPCs and all your traffic in the given CIDR range will then be routed over this secure, encrypted connection.

VPN Setup
---------
![Aws Alicloud VPN Architecture](https://i.imgur.com/x3i3MC7.png)

Setting up a VPN connection mainly involves setting up the following components in both AWS and Alicloud:

- VPN Gateway
- Customer Gateway
- VPN Connection
- Connection Route

First and foremost, following are the cluster specific variables that we will need for AWS and Alicloud:

### Variables and Cluster Definition
```hcl
# Default region: Singapore
variable "aws_vpc" {
  type = object({
    region    = string
    profile   = string
    vpc_id    = string
    cidr      = string
    subnet_id = string
  })
  default = {
    region    = "ap-southeast-1"
    profile   = "aws-profile"
    vpc_id    = "123456789"
    cidr      = "172.10.0.0/16"
    subnet_id = "subnet-123"
  }
}
# Default region: Singapore
# vswitch: AWS subnet equivalent in Alicloud
variable "alicloud_vpc" {
  type = object({
    region      = string
    profile     = string
    vpc_id      = string
    cidr        = string
    vswitch_id  = string
  })
  default = {
    region      = "ap-southeast-1"
    profile     = "alicloud-profile"
    vpc_id      = "987654321"
    cidr        = "172.20.0.0/16"
    vswitch_id  = "vswitch-123"
  }
}
```

### Terraform Providers for AWS and Alicloud
```hcl
provider "aws" {
  region  = var.aws_vpc.region
  version = "~> 2.45.0"
  profile = var.aws_vpc.profile
}
provider "alicloud" {
  region  = var.alicloud_vpc.region
  version = "1.71.1"
  profile = var.alicloud_vpc.profile
}
```

The first step is creating VPN Gateways in both Alicloud and AWS:

```hcl
resource "alicloud_vpn_gateway" "aws_vpn_gateway" {
  name                 = "AWS-VPN-Gateway"
  vpc_id               = var.alicloud_vpc.vpc_id
  bandwidth            = "10"
  enable_ssl           = false
  instance_charge_type = "PostPaid"
  description          = "AWS-VPN-Gateway"
  vswitch_id           = var.alicloud_vpc.vswitch_id
}
resource "aws_vpn_gateway" "alicloud_vpn_gateway" {
  vpc_id = var.aws_vpc.vpc_id
  tags = {
    Name = "Alicloud-VPN-GW"
  }
}
```

## VPN Setup in AWS

Creating the VPN Gateway will give us a publically accessible IP address of that gateway. In the first step, we will use the IP address of the Alicloud VPN Gateway to setup AWS side of things. Later on, we will repeat the same process in for Alicloud as well.

### AWS Customer Gateway
According to AWS:
> A customer gateway is a resource in AWS that provides information to AWS about your Customer Gateway Device
A Customer Gateway basically lets AWS know about the remote/destination address where the traffic should be forwarded if the destination IP belongs to the Alicloud CIDR range
```hcl
resource "aws_customer_gateway" "alicloud_vpn_gw" {
  bgp_asn    = 65000
  ip_address = alicloud_vpn_gateway.aws_vpn_gateway.internet_ip
  type       = "ipsec.1"
  tags = {
    Name = "alicloud-customer-gateway"
  }
}
```

### VPN Connection

![You Shall Not Pass](https://media.giphy.com/media/njYrp176NQsHS/giphy-downsized-large.gif)

A VPN Connection resource in AWS creates 2 _Tunnels_ between your VPC and the remote network (Alicloud Network represented by `customer_gateway_id` in this case). AWS will create 2 tunnels for redundancy. In case one of the tunnels goes down, the traffic is automatically routed through the other tunnel
```hcl
resource "aws_vpn_connection" "alicloud_vpn_connection" {
  vpn_gateway_id      = aws_vpn_gateway.alicloud_vpn_gateway.id
  customer_gateway_id = aws_customer_gateway.alicloud_vpn_gw.id
  type                = "ipsec.1"
  static_routes_only  = true
}
```

### VPN Connection Route Entry
This entry tells the VPN connection created in the previous step about the CIDR range of the destination
```hcl
resource "aws_vpn_connection_route" "alicloud" {
  destination_cidr_block = var.alicloud_vpc.cidr
  vpn_connection_id      = aws_vpn_connection.alicloud_vpn_connection.id
}
```

### AWS Route Table Modification
Next we need to fetch the route table of the private subnet and modify the route table to tell AWS to forward all the traffic ,belonging to the CIDR range of the destination, to the VPN Gateway that we created above
```hcl
data "aws_route_table" "aws_private_subnet_rt" {
  subnet_id = var.aws_vpc.subnet_id
}
resource "aws_route" "r" {
  route_table_id            = data.aws_route_table.aws_private_subnet_rt.id
  destination_cidr_block    = var.alicloud_vpc.cidr
  gateway_id = aws_vpn_gateway.alicloud_vpn_gateway.id
}
```

Once the AWS setup is done, we are going to repeat the same steps for Alicloud as well. I am not going to explain the terminologies again for Alicloud as they are more or less the same.

## VPN Setup in Alicloud
First of all, we will create 2 customer gateways in Alicloud - one for each of the _Tunnels_ created by the _VPN Connection_ in AWS. The `ip_address` parameter will contain the IP address of each of the tunnels

### Customer Gateway
```hcl
resource "alicloud_vpn_customer_gateway" "aws_customer_gateway_1" {
  name        = "AWSCustomerGateway1"
  ip_address  = aws_vpn_connection.alicloud_vpn_connection.tunnel1_address
  description = "AWSCustomerGateway1"
}
resource "alicloud_vpn_customer_gateway" "aws_customer_gateway_2" {
  name        = "AWSCustomerGateway2"
  ip_address  = aws_vpn_connection.alicloud_vpn_connection.tunnel2_address
  description = "AWSCustomerGateway2"
}
```

### VPN Connection
```hcl
# `effect_immediately` parameter determines weather to delete a successfully negotiated IPsec tunnel and initiate a negotiation again
resource "alicloud_vpn_connection" "ipsec_connection_1" {
  name                = "IPSecConnection1"
  vpn_gateway_id      = alicloud_vpn_gateway.aws_vpn_gateway.id
  customer_gateway_id = alicloud_vpn_customer_gateway.aws_customer_gateway_1.id
  local_subnet        = [var.alicloud_vpc.cidr]
  remote_subnet       = [var.aws_vpc.cidr]
  effect_immediately  = true
  ike_config {
    ike_auth_alg  = "sha1"
    ike_enc_alg   = "aes"
    ike_version   = "ikev1"
    ike_mode      = "main"
    ike_lifetime  = 86400
    psk           = aws_vpn_connection.alicloud_vpn_connection.tunnel1_preshared_key
    ike_pfs       = "group2"
    ike_local_id = alicloud_vpn_gateway.aws_vpn_gateway.internet_ip
    ike_remote_id = aws_vpn_connection.alicloud_vpn_connection.tunnel1_address
  }
  ipsec_config {
    ipsec_pfs      = "group2"
    ipsec_enc_alg  = "aes"
    ipsec_auth_alg = "sha1"
    ipsec_lifetime = 86400
  }
}
resource "alicloud_vpn_connection" "ipsec_connection_2" {
  name                = "IPSecConnection2"
  vpn_gateway_id      = alicloud_vpn_gateway.aws_vpn_gateway.id
  customer_gateway_id = alicloud_vpn_customer_gateway.aws_customer_gateway_2.id
  local_subnet        = [var.alicloud_vpc.cidr]
  remote_subnet       = [var.aws_vpc.cidr]
  effect_immediately  = true
  ike_config {
    ike_auth_alg  = "sha1"
    ike_enc_alg   = "aes"
    ike_version   = "ikev1"
    ike_mode      = "main"
    ike_lifetime  = 86400
    psk           = aws_vpn_connection.alicloud_vpn_connection.tunnel2_preshared_key
    ike_pfs       = "group2"
    ike_local_id = alicloud_vpn_gateway.aws_vpn_gateway.internet_ip
    ike_remote_id = aws_vpn_connection.alicloud_vpn_connection.tunnel2_address
  }
  ipsec_config {
    ipsec_pfs      = "group2"
    ipsec_enc_alg  = "aes"
    ipsec_auth_alg = "sha1"
    ipsec_lifetime = 86400
  }
}
```

Although, only a few of the above parameters are mandatory for making the request, have put in the exhaustive list just to give you guys an idea of what the parameters are.

### VPN Connection Route Entry
```hcl
resource "alicloud_vpn_route_entry" "alicloud_vpn_route_entry_1" {
  vpn_gateway_id = alicloud_vpn_gateway.aws_vpn_gateway.id
  route_dest     = var.aws_vpc.cidr
  next_hop       = alicloud_vpn_connection.ipsec_connection_1.id
  weight         = 0
  publish_vpc    = true
}
resource "alicloud_vpn_route_entry" "alicloud_vpn_route_entry_2" {
  vpn_gateway_id = alicloud_vpn_gateway.aws_vpn_gateway.id
  route_dest     = var.aws_vpc.cidr
  next_hop       = alicloud_vpn_connection.ipsec_connection_2.id
  weight         = 100
  publish_vpc    = true
}
```
