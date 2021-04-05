#!/bin/bash

# This installs certificates with the DB.

set -e

# User vars
installers_bucket="${installers_bucket}" # TODO these must become vars
deadlineuser_name="${deadlineuser_name}" # TODO these must become vars
deadline_version="${deadline_version}" # TODO these must become vars
dbport="27100"
db_host_name="deadlinedb.service.consul" # TODO these must become vars
deadline_proxy_certificate="Deadline10RemoteClient.pfx"
resourcetier="${resourcetier}"

# Script vars (implicit)
attempts=5
deadline_proxy_root_dir="$db_host_name:4433"
deadline_client_certificate_basename="${deadline_client_certificate%.*}"
deadline_linux_installers_tar="/tmp/Deadline-$deadline_version-linux-installers.tar" # temp dir since we just keep the extracted contents for repeat installs.
deadline_linux_installers_filename="$(basename $deadline_linux_installers_tar)"
deadline_linux_installers_basename="${deadline_linux_installers_filename%.*}"
deadline_installer_dir="/home/$deadlineuser_name/Downloads/$deadline_linux_installers_basename"
deadline_client_installer_filename="DeadlineClient-$deadline_version-linux-x64-installer.run"

# # set hostname
# cat /etc/hosts | grep -m 1 "127.0.0.1   $db_host_name" || echo "127.0.0.1   $db_host_name" | sudo tee -a /etc/hosts
# sudo hostnamectl set-hostname $db_host_name

# Functions
function has_yum {
  [[ -n "$(command -v yum)" ]]
}
function has_apt_get {
  [[ -n "$(command -v apt-get)" ]]
}
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
function retrieve_file {
  local -r source_path="$1"
  if [[ -z "$2" ]]; then
    local -r target_path="$source_path"
  else
    local -r target_path="$2"
  fi
  local -r response=$(retry \
  "vault kv get -format=json /$resourcetier/deadline/client_cert_files/$source_path" \
  "Trying to read secret from vault")
  sudo mkdir -p $(dirname $target_path) # ensure the directory exists
  # echo $response | jq -r .data.data | sudo tee $target_path # retrieve full json blob to later pass permissions if required.
  echo $response | jq -r .data.data.file | base64 --decode | sudo tee $target_path
  # skipping permissions
}

echo "Waiting for consul deadlinedb service..."
until consul catalog services | grep -m 1 "deadlinedb"; do sleep 1 ; done

### Vault Auth IAM Method CLI
export VAULT_ADDR=https://vault.service.consul:8200
retry \
  "vault login --no-print -method=aws header_value=vault.service.consul role=${example_role_name}" \
  "Waiting for Vault login"
echo "Aquiring vault data..."

# Retrieve previously generated secrets from Vault.  Would be better if we can use vault as an intermediary to generate certs.
retrieve_file "/opt/Thinkbox/certs/Deadline10RemoteClient.pfx"
# Revoke token
vault token revoke -self

### Install Deadline
sudo mkdir -p "/home/$deadlineuser_name/Downloads"
sudo chown $deadlineuser_name:$deadlineuser_name "/home/$deadlineuser_name/Downloads"

# Download Deadline
if [[ -f "$deadline_linux_installers_tar" ]]; then
    echo "File already exists: $deadline_linux_installers_tar"
else
    aws s3api head-object --bucket $installers_bucket --key "Deadline-$deadline_version-linux-installers.tar"
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "...Downloading Deadline from: $installers_bucket"
        aws s3api get-object --bucket $installers_bucket --key "$deadline_linux_installers_filename" "$deadline_linux_installers_tar"
    else
        echo "...Downloading Deadline from: thinkbox-installers"
        aws s3api get-object --bucket thinkbox-installers --key "Deadline/$deadline_version/Linux/$deadline_linux_installers_basename" "$deadline_linux_installers_tar"
    fi
fi

# Directories and permissions
sudo mkdir -p /opt/Thinkbox
sudo chown $deadlineuser_name:$deadlineuser_name /opt/Thinkbox
sudo chmod u=rwX,g=rX,o-rwx /opt/Thinkbox

# Client certs live here
deadline_client_certificates_location="/opt/Thinkbox/certs"
sudo mkdir -p "$deadline_client_certificates_location"
sudo chown $deadlineuser_name:$deadlineuser_name $deadline_client_certificates_location
sudo chmod u=rwX,g=rX,o-rwx $deadline_client_certificates_location

sudo mkdir -p $deadline_installer_dir

# Extract Installer
sudo tar -xvf $deadline_linux_installers_tar -C $deadline_installer_dir

# sudo apt-get install -y xdg-utils
# sudo apt-get install -y lsb # required for render nodes as well
sudo mkdir -p /usr/share/desktop-directories

# Install Deadline Worker
sudo $deadline_installer_dir/$deadline_client_installer_filename \
--mode unattended \
--debuglevel 2 \
--prefix /opt/Thinkbox/Deadline10 \
--connectiontype Remote \
--noguimode true \
--licensemode UsageBased \
--launcherdaemon true \
--slavestartup 1 \
--daemonuser $deadlineuser_name \
--enabletls true \
--tlsport 4433 \
--httpport 8080 \
--proxyrootdir $deadline_proxy_root_dir \
--proxycertificate $deadline_client_certificates_location/$deadline_proxy_certificate
# --proxycertificatepassword {{ deadline_proxy_certificate_password }}

# finalize permissions post install:
sudo chown $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/certs/*
sudo chmod u=wr,g=r,o-rwx /opt/Thinkbox/certs/*
sudo chmod u=wr,g=r,o=r /opt/Thinkbox/certs/ca.crt

# sudo service deadline10launcher restart

echo "Validate that a connection with the database can be established with the config"
/opt/Thinkbox/DeadlineDatabase10/mongo/application/bin/deadline_mongo --eval 'printjson(db.getCollectionNames())'
