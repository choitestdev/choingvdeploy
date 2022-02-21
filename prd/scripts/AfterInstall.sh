#!/bin/bash

## Set variables
WAS_HOME="/was/www/web1/ROOT"
REGION="ap-northeast-2"
DISTRIBUTION_ID="E2DIOZORJWVUKW"  # user-prd
S3_BUCKET="s3-prd-user-front-static"
AWS_CLI="/usr/local/bin/aws"
BASE_DIR="/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive"

## Stop tomcat service
service tomcat stop

## validate service healthy
while true;
do
  EVAL=$(ps -ef | grep tomcat | grep Bootstrap 2> /dev/null)
  if [[ -z ${EVAL} ]]; then
    sleep 1
  else
    echo "Deployment complete"
    break
  fi
done

## Wait for WAS_HOME is unpacked
while true;
do
  if [[ -d ${WAS_HOME} ]]; then
    break
  else
    sleep 1
  fi
done

sleep 10

## Sync files between local and S3
(${AWS_CLI} s3 sync ${WAS_HOME} s3://${S3_BUCKET}/static/ --delete --region $REGION \
  --exclude "hmgTest/*" --exclude "html/*" --exclude "java_backup/*" \
  --exclude "debug.log" --exclude "gulpfile.js" --exclude "index.html" --exclude "landing.html" \
  --exclude "package-lock.json" --exclude "package.json" --exclude "readme.jsp" --exclude "uni_code.jsp" \
  --exclude "upload/*" --exclude "favicon.ico" --exclude "META-INF/*" --exclude "WEB-INF/*" --exclude "index.jsp") > $BASE_DIR/modifyFiles

# CloudFront invalidation
unset EVAL
tr -d '\r' < ${BASE_DIR}/modifyFiles | grep 's3://' | grep -Ev '\.do|\.jsp' | awk -F 's3:\\/\\/s3-prd-user-front-static\\/static' '{print $2}' | while IFS= read -r line; do PATHS_STR="${PATHS_STR} $line"; echo $PATHS_STR > ${BASE_DIR}/paths.str ; done

PATHS_STR=$(cat ${BASE_DIR}/paths.str 2> /dev/null)
TEST=$(echo $PATHS_STR | tr -d '"')
if [[ -n "$TEST" ]]; then
    ID=$(${AWS_CLI} cloudfront create-invalidation --distribution-id ${DISTRIBUTION_ID} --paths ${PATHS_STR} --region $REGION --query 'Invalidation.Id' | tr -d '"')

    ## Validate create-invalidation progress
    while true;
    do
      EVAL=$(${AWS_CLI} cloudfront get-invalidation --id ${ID} --distribution-id ${DISTRIBUTION_ID} | grep "Completed")
      if [[ -z ${EVAL} ]]; then
        sleep 1
      else
        echo "CloudFront invalidation completed"
        break
      fi
    done
fi
