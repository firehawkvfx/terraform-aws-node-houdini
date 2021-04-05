#!/bin/bash

set -e
exec > >(tee -a /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# User Defaults: these will be replaced with terraform template vars, defaults are provided to allow copy / paste directly into a shell for debugging.  These values will not be used when deployed.
deadlineuser_name="deadlineuser"
resourcetier="dev"
installers_bucket="software.$resourcetier.firehawkvfx.com"
deadline_version="10.1.9.2"

# User Vars: Set by terraform template
deadlineuser_name="${deadlineuser_name}"
resourcetier="${resourcetier}"
installers_bucket="${installers_bucket}"
deadline_version="${deadline_version}"

# Script vars (implicit)
VAULT_ADDR=https://vault.service.consul:8200
client_cert_file_path="/opt/Thinkbox/certs/Deadline10RemoteClient.pfx"
client_cert_vault_path="$resourcetier/deadline/client_cert_files/$client_cert_file_path"
installer_file="install-deadline-worker.sh"
installer_path="/home/$deadlineuser_name/Downloads/$installer_file"

# Functions
function has_yum {
  [[ -n "$(command -v yum)" ]]
}
function has_apt_get {
  [[ -n "$(command -v apt-get)" ]]
}
# A retry function that attempts to run a command a number of times and returns the output
function retry {
  local -r cmd="$1"
  local -r description="$2"
  attempts=5
  for i in $(seq 1 $attempts); do
    echo "$description"
    # The boolean operations with the exit status are there to temporarily circumvent the "set -e" at the
    # beginning of this script which exits the script immediatelly for error status while not losing the exit status code
    output=$(eval "$cmd") && exit_status=0 || exit_status=$?
    errors=$(echo "$output") | grep '^{' | jq -r .errors
    echo "$output"
    if [[ $exit_status -eq 0 && -z "$errors" ]]; then
      echo "$output"
      return
    fi
    echo "$description failed. Will sleep for 10 seconds and try again."
    sleep 10
  done;
  echo "$description failed after $attempts attempts. exit_status: $exit_status"
  exit $exit_status
}
function retrieve_file {
  echo "source var"
  local -r source_path="$1"
  if [[ -z "$2" ]]; then
    local -r target_path="$source_path"
  else
    local -r target_path="$2"
  fi
  echo "response:"
  local -r response=$(retry \
  "vault kv get -format=json $source_path/file" \
  "Trying to read secret from vault")

  echo "$response"
  echo "mkdir: $(dirname $target_path)"
  sudo mkdir -p "$(dirname $target_path)" # ensure the directory exists
  # echo $response | jq -r .data.data | sudo tee $target_path # retrieve full json blob to later pass permissions if required.
  # echo "decode"
  # # jq seems to fail decoding some certs, so we use python instead.
  # decoded="$(blob=$response python -c \"import os,json; blob=os.environ['blob']; print( json.loads(blob)['data']['data']['file'] )\" | base64 --decode)"
  # decoded="$(blob=$response python -c \"import os,json; print(os.environ['blob'])\")"
  
  # raw=$(echo "$response" | jq -r '.data.data.file')
  # echo "decode"
  # decode=$(echo "$raw" | base64 --decode)
  # echo "write to file"
  # echo "$decode" | sudo tee $target_path
  # echo "write output"
  # raw=$( python -c "import json; blob=json.loads($response); print( blob[\"data\"][\"data\"][\"file\"] )" )
  echo "Check file path is writable"
  if [[ ! -f "$target_path" ]]; then 
    touch "$target_path"
  else
    echo "Error: Path not writable: $target_path "
  fi
  if [[ -f "$target_path" ]]; then
    sudo chmod u+w "$target_path"
  else
    echo "Error: path does not exist, var may not be a file: $target_path "
  fi
  # sudo chmod u+w $target_path
  echo "Write file content: single operation"
  # echo $(retry \
  # "vault kv get -format=json $source_path" \
  # "Trying to read secret from vault") | jq -r '.data.data.file' | base64 --decode > $target_path
  # echo "Write file content from var"
  # echo "$response" | jq -r '.data.data.file' | base64 --decode > $target_path
  echo "$response" | base64 --decode > $target_path
  if [[ ! -f "$target_path" ]] || [[ -z "$(cat $target_path)" ]]; then
    echo "Error: no file or empty result at $target_path"
    exit 1
  fi
  echo "retrival done."
  # skipping permissions
}

### Centos 7 fix: Failed dns lookup can cause sudo commands to slowdown
if $(has_yum); then
    hostname=$(hostname -s) 
    echo "127.0.0.1   $hostname.${aws_internal_domain} $hostname" | tee -a /etc/hosts
    hostnamectl set-hostname $hostname.${aws_internal_domain} # Red hat recommends that the hostname uses the FQDN.  hostname -f to resolve the domain may not work at this point on boot, so we use a var.
    # systemctl restart network # we restart the network later, needed to update the host name
fi

### Create deadlineuser
function add_sudo_user() {
  local -r user_name="$1"
  if $(has_apt_get); then
    sudo_group=sudo
  elif $(has_yum); then
    sudo_group=wheel
  else
    echo "ERROR: Could not find apt-get or yum."
    exit 1
  fi
  echo "Ensuring user exists: $user_name with groups: $sudo_group $user_name"
  if id "$user_name" &>/dev/null; then
    echo 'User found.  Ensuring user is in sudoers.'
    sudo usermod -a -G $sudo_group $user_name
  else
      echo 'user not found'
      sudo useradd -m -d /home/$user_name/ -s /bin/bash -G $sudo_group $user_name
  fi
  echo "Adding user as passwordless sudoer."
  touch "/etc/sudoers.d/98_$user_name"; grep -qxF "$user_name ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/98_$user_name || echo "$user_name ALL=(ALL) NOPASSWD:ALL" >> "/etc/sudoers.d/98_$user_name"
  sudo -i -u $user_name mkdir -p /home/$user_name/.ssh
  # Generate a public and private key - some tools can fail without one.
  rm -frv /home/$user_name/.ssh/id_rsa*
  sudo -i -u $user_name bash -c "ssh-keygen -q -b 2048 -t rsa -f /home/$user_name/.ssh/id_rsa -C \"\" -N \"\""  
}
add_sudo_user $deadlineuser_name

printf "\n...Waiting for consul deadlinedb service before attempting to retrieve Deadline remote cert.\n\n"

until consul catalog services | grep -m 1 "deadlinedb"; do sleep 1 ; done

### Vault Auth IAM Method CLI
retry \
  "vault login --no-print -method=aws header_value=vault.service.consul role=${example_role_name}" \
  "Waiting for Vault login"
echo "Aquiring vault data... $client_cert_vault_path to $client_cert_file_path"
# Retrieve previously generated secrets from Vault.  Would be better if we can use vault as an intermediary to generate certs.
retrieve_file "$client_cert_vault_path" "$client_cert_file_path"
echo "Revoking vault token..."
vault token revoke -self

### Install Deadline
# Client
mkdir -p "$(dirname $installer_path)"
aws s3api get-object --bucket "$installers_bucket" --key "$installer_file" "$installer_path"
chown $deadlineuser_name:$deadlineuser_name $installer_path
chmod u+x $installer_path
sudo -i -u $deadlineuser_name installers_bucket="$installers_bucket" deadlineuser_name="$deadlineuser_name" deadline_version="$deadline_version" $installer_path

