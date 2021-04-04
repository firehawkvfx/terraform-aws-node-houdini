#!/bin/bash

set -e
# Send the log output from this script to user-data.log, syslog, and the console. From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee -a /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

resourcetier=${resourcetier}
attempts=5

# Log the given message. All logs are written to stderr with a timestamp.
function log {
 local -r message="$1"
 local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
 >&2 echo -e "$timestamp $message"
}

# A retry function that attempts to run a command a number of times and returns the output
function retry {
  local -r cmd="$1"
  local -r description="$2"

  for i in $(seq 1 $attempts); do
    log "$description"

    # The boolean operations with the exit status are there to temporarily circumvent the "set -e" at the
    # beginning of this script which exits the script immediatelly for error status while not losing the exit status code
    output=$(eval "$cmd") && exit_status=0 || exit_status=$?
    errors=$(echo "$output") | grep '^{' | jq -r .errors

    log "$output"

    if [[ $exit_status -eq 0 && -z "$errors" ]]; then
      echo "$output"
      return
    fi
    log "$description failed. Will sleep for 10 seconds and try again."
    sleep 10
  done;

  log "$description failed after $attempts attempts."
  exit $exit_status
}

echo "Aquiring vault data..."

function retrieve_file {
  local -r source_path="$1"
  if [[ -z "$2" ]]; then
    local -r target_path="$source_path"
  else
    local -r target_path="$2"
  fi
  # target_path=/usr/local/openvpn_as/scripts/seperate/ca.crt
  # vault kv get -format=json /${resourcetier}/files/$target_path > /usr/local/openvpn_as/scripts/seperate/ca_test.crt

  local -r response=$(retry \
  "vault kv get -format=json /$resourcetier/deadlinedb/client_cert_files/$source_path" \
  "Trying to read secret from vault")
  sudo mkdir -p $(dirname $target_path) # ensure the directory exists
  echo $response | jq -r .data.data | sudo tee $target_path # retrieve full json blob to later pass permissions if required.
  # skipping permissions
  # local -r permissions=$(echo $response | jq -r .data.data.permissions)
  # local -r uid=$(echo $response | jq -r .data.data.uid)
  # local -r gid=$(echo $response | jq -r .data.data.gid)
  # echo "Setting:"
  # echo "uid:$uid gid:$gid permissions:$permissions target_path:$target_path"
  # sudo chown $uid:$gid $target_path
  # sudo chmod $permissions $target_path
}

# Retrieve previously generated secrets from Vault.  Would be better if we can use vault as an intermediary to generate certs.
retrieve_file "/opt/Thinkbox/certs/Deadline10RemoteClient.pfx"

# Install Deadline DB and RCS with certificates
sudo -u ubuntu git clone --branch ${deadline_installer_script_branch} ${deadline_installer_script_repo} /home/ubuntu/packer-firehawk-amis
sudo -u ubuntu /home/ubuntu/packer-firehawk-amis/modules/firehawk-ami/scripts/deadline_worker_install.sh