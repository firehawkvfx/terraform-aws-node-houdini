# A vault client host with consul registration and signed host keys from vault.

data "aws_region" "current" {}
data "aws_s3_bucket" "software_bucket" {
  bucket = "software.${var.bucket_extension}"
}
# resource "aws_s3_bucket_object" "update_scripts" {
#   for_each = fileset("${path.module}/scripts/", "*")
#   bucket   = data.aws_s3_bucket.software_bucket.id
#   key      = each.value
#   source   = "${path.module}/scripts/${each.value}"
#   etag     = filemd5("${path.module}/scripts/${each.value}")
# }
locals {
  resourcetier           = var.common_tags["resourcetier"]
  client_cert_file_path  = "/opt/Thinkbox/certs/Deadline10RemoteClient.pfx"
  client_cert_vault_path = "${local.resourcetier}/deadline/client_cert_files${local.client_cert_file_path}"
}
data "template_file" "user_data_auth_client" {
  template = format("%s%s",
    file("${path.module}/user-data-iam-auth-ssh-host-consul.sh"),
    file("${path.module}/user-data-install-deadline-worker-cert.sh")
  )
  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    aws_internal_domain      = var.aws_internal_domain
    aws_external_domain      = "" # External domain is not used for internal hosts.
    example_role_name        = "rendernode-vault-role"

    deadlineuser_name                = "deadlineuser"
    deadline_version                 = var.deadline_version
    installers_bucket                = "software.${var.bucket_extension}"
    resourcetier                     = local.resourcetier
    deadline_installer_script_repo   = "https://github.com/firehawkvfx/packer-firehawk-amis.git"
    deadline_installer_script_branch = "deadline-immutable" # TODO This must become immutable - version it

    client_cert_file_path  = local.client_cert_file_path
    client_cert_vault_path = local.client_cert_vault_path
  }
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
  user_data              = data.template_file.user_data_auth_client.rendered
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
  private_ip                             = element(concat(aws_instance.node_centos7_houdini.*.private_ip, list("")), 0)
  id                                     = element(concat(aws_instance.node_centos7_houdini.*.id, list("")), 0)
  # node_centos7_houdini_security_group_id = element(concat(aws_security_group.node_centos7_houdini.*.id, list("")), 0)
  # vpc_security_group_ids                 = [local.node_centos7_houdini_security_group_id]
}

