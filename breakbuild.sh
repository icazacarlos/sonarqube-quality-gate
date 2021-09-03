#!/usr/bin/env bash
# this script checks the status of a quality gate for a particular analysisID
# approach taken from https://docs.sonarqube.org/display/SONARQUBE53/Breaking+the+CI+Build
# When SonarScanner executes, the compute engine task is given an id
# The status of this task, and analysisId for the task can be checked at
# /api/ce/task?id=taskid
# When the status is SUCCESS, the quality gate status can be checked at
# /api/qualitygates/project_status?analysisId=analysisId
set -o errexit
set -o pipefail
set -o nounset

# =====================

success() {
  echo -e "\e[32m\e[1m${1}\e[0m"
}

warning() {
  echo -e "\e[33m\e[1m${1}\e[0m"
}

error() {
  echo -e "\e[91m\e[1m${1}\e[0m"
}

# =====================

IS_GIT_REPOSITORY=`git -C . rev-parse 2> /dev/null; echo $?`
PENDING_CHANGES=

if [[ ! $IS_GIT_REPOSITORY -eq 0 ]]; then
  error "Path is a no a Git repository"
  exit
fi

if [[ `git status --porcelain` ]]; then
  warning "There are files not committed yet"
  PENDING_CHANGES="dirty"
fi

BRANCH=`git rev-parse --abbrev-ref HEAD`
COMMIT=`git rev-parse HEAD | cut -c1-8`
HOSTNAME=`hostname`
VERSION=`awk -F'"' '/"version": ".+"/{ print $4; exit; }' package.json`
PROJECT_VERSION=${VERSION}-${BRANCH}-${COMMIT}-${HOSTNAME}-${PENDING_CHANGES}

# =====================

ORGANIZATION=

while getopts o: options
do
  case "${options}" in
    o) ORGANIZATION=${OPTARG};;
    \?) error "Error: Invalid option"
        exit;;
  esac
done

if [ -z "$ORGANIZATION" ]; then
   echo "Help"
   exit 1
fi

# =====================

CONFIG_PATH=~/.sonar/config/
CONFIG_FILE=${CONFIG_PATH}${ORGANIZATION}.sh

if [ ! -f "${CONFIG_FILE}" ]; then
  error "\nThe configuration for '${ORGANIZATION}' organization does not exist"
  exit 1
fi

echo "Loading configuration"
source "${CONFIG_FILE}"


if grep -iq "skipLint" <<< "${@}"; then
  warning "Skipping lint\n"
else
  echo "Linting source code"
  npm run lint:ci --if-present
fi

if grep -iq "skipTest" <<< "${@}"; then
  warning "Skipping unit tests\n"
else
  echo "Unit Testing"
  npm run test:ci --if-present
fi

echo "Running sonar scanner"
npm run sonar --if-present -- -Dsonar.host.url=${SONAR_INSTANCE} -Dsonar.login=${SONAR_ACCESS_TOKEN} -Dsonar.projectVersion=${PROJECT_VERSION} -Dsonar.branch.name=${BRANCH}

# =====================

# in newer versions of sonar scanner the default report-task.txt location may be different
REPORT_PATH=".scannerwork/report-task.txt"
#REPORT_PATH=".sonar/report-task.txt"
CE_TASK_ID_KEY="ceTaskId="

SLEEP_TIME=5

echo "QG Script --> Using SonarQube instance ${SONAR_INSTANCE}"

# get the compute engine task id
ce_task_id=$(cat $REPORT_PATH | grep $CE_TASK_ID_KEY | cut -d'=' -f2)
echo "QG Script --> Using task id of ${ce_task_id}"

if [ -z "$ce_task_id" ]; then
   error "QG Script --> No task id found"
   exit 1
fi

# grab the status of the task
# if CANCELLED or FAILED, fail the Build
# if SUCCESS, stop waiting and grab the analysisId
wait_for_success=true

while [ "${wait_for_success}" = "true" ]
do
  ce_status=$(curl -s -u "${SONAR_ACCESS_TOKEN}": "${SONAR_INSTANCE}"/api/ce/task?id=${ce_task_id} | jq -r .task.status)

  echo "QG Script --> Status of SonarQube task is ${ce_status}"

  if [ "${ce_status}" = "CANCELLED" ]; then
    error "QG Script --> SonarQube Compute job has been cancelled - exiting with error"
    exit 1
  fi

  if [ "${ce_status}" = "FAILED" ]; then
    error "QG Script --> SonarQube Compute job has failed - exiting with error"
    exit 1
  fi

  if [ "${ce_status}" = "SUCCESS" ]; then
    wait_for_success=false
  fi

  sleep "${SLEEP_TIME}"

done

ce_analysis_id=$(curl -s -u $SONAR_ACCESS_TOKEN: $SONAR_INSTANCE/api/ce/task?id=$ce_task_id | jq -r .task.analysisId)
echo "QG Script --> Using analysis id of ${ce_analysis_id}"

# get the status of the quality gate for this analysisId
qg_status=$(curl -s -u $SONAR_ACCESS_TOKEN: $SONAR_INSTANCE/api/qualitygates/project_status?analysisId="${ce_analysis_id}" | jq -r .projectStatus.status)

if [ "${qg_status}" == "OK" ]; then
  success "QG Script --> Quality Gate status is ${qg_status}"
else
  error "QG Script --> Quality gate is ${qg_status} - exiting with error"
  exit 1
fi
