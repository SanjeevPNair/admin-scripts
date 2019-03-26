#!/bin/bash
#
# [ 0x19e Networks ]
# Author: Robert W. Baumgartner <rwb@0x19e.net>
#
# install-client.sh : Install Bareos FileDaemon (client)
#
# NOTE: This script currently supports only APT on Debian and Debian-based distributions (ie. Ubuntu).

hash grep 2>/dev/null || { echo >&2 "You need to install grep. Aborting."; exit 1; }
hash awk 2>/dev/null || { echo >&2 "You need to install awk. Aborting."; exit 1; }
hash sudo 2>/dev/null || { echo >&2 "You need to install sudo. Aborting."; exit 1; }
hash wget 2>/dev/null || { echo >&2 "You need to install wget. Aborting."; exit 1; }
hash gpg 2>/dev/null || { echo >&2 "You need to install gnupg. Aborting."; exit 1; }
hash apt-get 2>/dev/null || { echo >&2 "You need to install apt. Aborting."; exit 1; }
hash tee 2>/dev/null || { echo >&2 "You need to install tee. Aborting."; exit 1; }
hash lsb_release 2>/dev/null || { echo >&2 "You need to install lsb-release. Aborting."; exit 1; }

# Get distro release version
UBUNTU_RELEASE=$(lsb_release -a 2>/dev/null | grep Release | awk '{print $2}')

# Configure the package name
PKGNAME="bareos-filedaemon"

# Configure remote package source
HTPROTO="http"
KEYNAME="Release.key"
SRC_PKG="xUbuntu_${UBUNTU_RELEASE}"
SRC_URL="download.bareos.org/bareos/release/latest/${SRC_PKG}"

# Configure package source installation
APT_DIR="/etc/apt/sources.list.d"
PKG_LST="${APT_DIR}/bareos.list"

# Configure apt-get arguments
APT_ARG="--verbose-versions --yes"

# Uncomment to run script when the package is already installed
#FORCE_INSTALL="true"

function check_installed()
{
  pkg_name="$1"
  if [ -z "${pkg_name}" ]; then
    echo >&2 "ERROR: Package name not provided to check script."
    exit 1
  fi

  if hash apt-cache 2>/dev/null; then
    if [ ! -z "$(apt-cache policy ${pkg_name} | grep -v '(none)' | grep Installed)" ]; then
      return 0
    fi
  fi

  return 1
}

function is_valid_protocol()
{
  proto_name="$1"
  if [ -z "${proto_name}" ]; then
    echo >&2 "No protocol string was specified."
    exit 1
  fi

  if echo "${proto_name}" | grep -qP '^[Hh][Tt][Tt][Pp]([Ss])?$'; then
    return 0
  fi

  echo >&2 "ERROR: Invalid HTTP protocol '${proto_name}'."
  return 1
}

function is_https()
{
  proto_name="$1"
  if [ -z "${proto_name}" ]; then
    echo >&2 "No protocol string was specified."
    exit 1
  fi

  if echo "${proto_name}" | grep -qP '^[Hh][Tt][Tt][Pp][Ss]$'; then
    # https protocol
    return 0
  fi

  # http protocol
  return 1
}

function valid_url()
{
  url="$1"
  if [ -z "${url}" ]; then
    echo >&2 "No URL string was specified."
    exit 1
  fi

  if wget -q "${url}" -O /dev/null; then
    return 0
  fi

  return 1
}

check_url()
{
  url="$1"
  if [ -z "${url}" ]; then
    echo >&2 "No URL string was specified."
    exit 1
  fi

  if ! valid_url "${url}"; then
    echo >&2 "ERROR: Invalid URL: '${url}'"
    exit 1
  fi
}

check_protocol()
{
  proto_name="$1"
  if [ -z "${proto_name}" ]; then
    echo >&2 "No protocol string was specified."
    exit 1
  fi

  if ! is_valid_protocol "$proto_name"; then
    exit 1
  fi

  if is_https "$proto_name"; then
    if hash apt-get 2>/dev/null; then
      if ! check_installed "apt-transport-https"; then
        echo >&2 "ERROR: Must install apt-transport-https for HTTPS protocol support."
        exit 1
      fi
    fi
  fi
}

check_etckeeper()
{
  # git handling for etckeeper (check if /etc/.git exists)
  if [ -d /etc/.git  ] && hash git 2>/dev/null; then
    if `git -C "/etc" rev-parse > /dev/null 2>&1`; then
      # check /etc/apt for modifications
      # if there are changes, commit them
      if [[ "$(git --git-dir=/etc/.git --work-tree=/etc status --porcelain -- /etc/apt|egrep '^(M| M)')" != "" ]]; then
        echo "Auto-commit changes to /etc/apt (directory under version control) ..."
        pushd /etc > /dev/null 2>&1
        sudo git add --all /etc/apt
        sudo git commit -v -m "apt: add bareos package source"
        popd > /dev/null 2>&1
      fi
    fi
  fi
}

install_key_from_url()
{
  key_url="$1"
  if [ -z "${key_url}" ]; then
    echo >&2 "No key URL was specified."
    exit 1
  fi

  # check if the key is already installed
  KEY_RW=$(wget -qO - "${KEY_URL}")
  if [ -z "${KEY_RW}" ]; then
    echo >&2 "Failed to retrieve signing key from ${KEY_URL}"
    exit 1
  fi
  if ! echo "${KEY_RW}" | gpg --list-packets > /dev/null 2>&1; then
    echo >&2 "Invalid key returned from URL ${KEY_URL}"
    exit 1
  fi

  GPG_RW=$(echo "${KEY_RW}" | gpg --with-fingerprint --keyid-format SHORT 2>/dev/null | grep -P '^pub' | head -n1)
  KEY_ID=$(echo "${GPG_RW}" | cut -d' ' -f5- | awk '{$1=$1};1')

  KEY_TP=$(echo "${GPG_RW}" | awk '{ print $2 }' | awk '{$1=$1};1')
  KEY_SZ=$(echo "${KEY_TP}" | cut -d/ -f1)
  KEY_FP=$(echo "${KEY_TP}" | cut -d/ -f2)

  KEY_LIST=$(apt-key list --keyid-format SHORT 2>/dev/null)
  if echo "${KEY_LIST}" | grep "${KEY_FP}" > /dev/null 2>&1; then
    echo "Found signing key  : ${KEY_ID}"
    echo "Key fingerprint    : ${KEY_FP}"
    echo "Key size and type  : ${KEY_SZ}"
    return
  fi

  # add the release key
  echo "Retrieve signing key from ${KEY_URL} ..."
  echo "Key identifier     : ${KEY_ID}"
  echo "Key fingerprint    : ${KEY_FP}"
  echo "Key size and type  : ${KEY_SZ}"

  echo "${KEY_RW}" | sudo apt-key add -
  if ! [ $? -eq 0 ]; then
    exit 1
  fi
}

# Configure some variables
PKG_SRC="${SRC_URL}/"
PKG_KEY="${SRC_URL}/${KEYNAME}"

PKG_URL="${HTPROTO}://${PKG_SRC}"
KEY_URL="${HTPROTO}://${PKG_KEY}"
DEB_TXT="deb ${PKG_URL} ./"

# Check required settings
if [ -z "${UBUNTU_RELEASE}" ]; then
  echo >&2 "ERROR: Unable to determine Ubuntu release."
  exit 1
fi
if [ -z "${PKGNAME}" ]; then
  echo >&2 "ERROR: Unable to determine package name."
  exit 1
fi

# Validate package source settings
check_protocol "${HTPROTO}"
check_url      "${PKG_URL}"
check_url      "${KEY_URL}"

# check if the package is already installed
if [ "${FORCE_INSTALL}" != "true" ] && check_installed "${PKGNAME}"; then
  echo "The package '${PKGNAME}' is already installed on the current system."
  exit 0
fi

echo "Installing Bareos FileDaemon backup client for Ubuntu ${UBUNTU_RELEASE} ..."

# install signing key
install_key_from_url "${KEY_URL}"

# print some details about source configuration
echo "Configuration file : ${PKG_LST}"
echo "Package repository : ${PKG_URL}"

# add the package source if not already configured
CUR_CFG=$(grep -RF "${PKG_SRC}" "${APT_DIR}/" 2>/dev/null | grep -v '\#' | head -n1 | cut -d: -f1)
if [ ! -z "${CUR_CFG}" ] && [ ! -e "${CUR_CFG}" ]; then
  echo >&2 "ERROR: Something went wrong while looking for source configuration."
  exit 1
fi

# add source if no existing configuration was found
if [ -z "${CUR_CFG}" ]; then
  echo "Configure missing package source ..."
  echo "${DEB_TXT}" | sudo tee -a "${PKG_LST}"
  if ! [ $? -eq 0 ]; then
    exit 1
  fi

  # update the package cache
  echo "Updating package list ..."
  sudo apt-get update > /dev/null 2>&1
  if ! [ $? -eq 0 ]; then
    exit 1
  fi
fi

# check if /etc is under version control
check_etckeeper

# install the actual package
echo "Installing package '${PKGNAME}' ..."
sudo apt-get ${APT_ARG} install ${PKGNAME}
if ! [ $? -eq 0 ]; then
  echo >&2 "ERROR: Failed to install Bareos client."
  exit 1
fi

if [ $? -eq 0 ]; then
  echo "Bareos FileDaemon (${PKGNAME}) installation successful."
fi

exit $?
