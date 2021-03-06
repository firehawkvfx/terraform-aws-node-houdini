include {
  path = find_in_parent_folders()
}

locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

dependency "data" {
  config_path = "../data"
  mock_outputs = {
    user_data_base64 = "fake-user-data"
  }
}

inputs = merge(
  local.common_vars.inputs,
  {
    user_data          = dependency.data.outputs.user_data_base64
  }
)

dependencies {
  paths = [
    "../data"
    ]
}

# skip = true