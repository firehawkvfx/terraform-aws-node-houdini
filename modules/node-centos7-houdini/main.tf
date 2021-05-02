# A vault client host with consul registration and signed host keys from vault.

data "aws_region" "current" {}
data "aws_s3_bucket" "software_bucket" {
  bucket = "software.${var.bucket_extension}"
}
data "terraform_remote_state" "rendernode_profile" { # read the arn with data.terraform_remote_state.packer_profile.outputs.instance_role_arn, or read the profile name with data.terraform_remote_state.packer_profile.outputs.instance_profile_name
  backend = "s3"
  config = {
    bucket = "state.terraform.${var.bucket_extension_vault}"
    key    = "firehawk-main/modules/terraform-aws-iam-profile-rendernode/terraform.tfstate"
    region = data.aws_region.current.name
  }
}
resource "aws_instance" "node_centos7_houdini" {
  count                  = var.create_vpc ? 1 : 0
  ami                    = var.node_centos7_houdini_ami_id
  instance_type          = var.instance_type
  key_name               = var.aws_key_name # The PEM key is disabled for use in production, can be used for debugging.  Instead, signed SSH certificates should be used to access the host.
  subnet_id              = tolist(var.private_subnet_ids)[0]
  tags                   = merge(map("Name", var.name), var.common_tags, local.extra_tags)
  user_data              = base64decode(var.user_data)
  iam_instance_profile   = data.terraform_remote_state.rendernode_profile.outputs.instance_profile_name
  vpc_security_group_ids = var.vpc_security_group_ids
  root_block_device {
    delete_on_termination = true
  }
}
locals {
  extra_tags = {
    role  = "node_centos7_houdini"
    route = "private"
  }
  private_ip = element(concat(aws_instance.node_centos7_houdini.*.private_ip, list("")), 0)
  id         = element(concat(aws_instance.node_centos7_houdini.*.id, list("")), 0)
  # node_centos7_houdini_security_group_id = element(concat(aws_security_group.node_centos7_houdini.*.id, list("")), 0)
  # vpc_security_group_ids                 = [local.node_centos7_houdini_security_group_id]
}

