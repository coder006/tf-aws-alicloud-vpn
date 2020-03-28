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