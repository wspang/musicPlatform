# set GCP credentials path to build in GCP
echo "set GOOGLE_APPLICATION_CREDENTIALS to .json file location"
# set terraform env variables for build
export TF_VAR_INGEST_CONFIG_SOURCE_PATH="./ingest/config.json"
export TF_VAR_INGEST_CODE_SOURCE_PATH="./ingest_cf_code.zip"

# create zip files for deployment 
zip -j $TF_VAR_INGEST_CODE_SOURCE_PATH ./ingest/*
# init, plan, and prompt for build on terraform
cd ./terraform
echo "initatiting terraform build"
terraform init
echo "planning terraform build"
terraform plan
echo "Do you wish to proceed with build?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) terraform apply; break;;
        No ) exit;;
    esac
done

# cleanup: remove zip files
cd ..
rm $TF_VAR_INGEST_CODE_SOURCE_PATH
