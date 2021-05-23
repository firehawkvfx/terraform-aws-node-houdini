include {
  path = find_in_parent_folders()
}

locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

dependency "terraform-aws-user-data-rendernode" {
  config_path = "../terraform-aws-user-data-rendernode"
  mock_outputs = {
    user_data_base64 = "fake-user-data"
  }
}

inputs = merge(
  local.common_vars.inputs,
  {
    user_data          = dependency.terraform-aws-user-data-rendernode.outputs.user_data_base64
  }
)

dependencies {
  paths = [
    "../terraform-aws-render-vpc-vault-vpc-peering",
    "../terraform-aws-deadline-db",
    "../terraform-aws-sg-rendernode/module",
    "../terraform-aws-user-data-rendernode",
    "../../../firehawk-main/modules/terraform-aws-sg-bastion",
    "../../../firehawk-main/modules/terraform-aws-sg-vpn",
    "../../../firehawk-main/modules/vault",
    "../../../firehawk-main/modules/terraform-aws-iam-profile-rendernode"
    ]
}

# skip = true