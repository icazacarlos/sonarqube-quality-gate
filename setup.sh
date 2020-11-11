#!/bin/bash

set -o errexit

CONFIG_PATH=~/.sonar/config/

mkdir -p "${CONFIG_PATH}"

echo -e "\n============================="
echo -e "   SonarQube Configuration"
echo -e "=============================\n"

echo "Organization name: "
read ORGANIZATION

CONFIG_FILE=${CONFIG_PATH}${ORGANIZATION}.sh

if [ -f "${CONFIG_FILE}" ]; then
  echo -e "\nThe configuration file for '${ORGANIZATION}' organization already exists"
  echo -e "\nConfiguration file: ${CONFIG_FILE}"
  exit 1
fi

echo -e "\nSonarQube URL: [http://localhost:9000]"
read sonar_host

if [ -z "$sonar_host" ]; then
  sonar_host="http://localhost:9000"
fi

echo -e "\nAccess Token: [0123456789]"
read sonar_token

if [ -z "$sonar_token" ]; then
  sonar_token="0123456789"
fi

cat <<EOT >> "${CONFIG_FILE}"
#!/bin/bash
export SONAR_INSTANCE=${sonar_host}
export SONAR_ACCESS_TOKEN=${sonar_token}
EOT

if [ -f "${CONFIG_FILE}" ]; then
  echo -e "\nThe configuration file for '${ORGANIZATION}' organization has been created"
  echo "Configuration file: ${CONFIG_FILE}"
fi
