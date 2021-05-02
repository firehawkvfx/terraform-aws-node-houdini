include {
  path = find_in_parent_folders()
}

locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

# inputs = local.common_vars.inputs

dependency "terraform-aws-user-data-rendernode" {
  config_path = "../terraform-aws-user-data-rendernode"
  mock_outputs = {
    user_data = "fake-user-data"
  }
}

inputs = merge(
  local.common_vars.inputs,
  {
    user_data          = dependency.terraform-aws-user-data-rendernode.outputs.user_data
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