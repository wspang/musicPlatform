##############################
###project wide variables#####
##############################
variable "PROJECT_ID" {
    type = string
    sensitive = true
}
variable "PROJECT" {
    type = string
    sensitive = true
}
variable "REGION" {
    default = "us-east1"
    type = string
    sensitive = false
}
variable "ZONE" {
    default = "b"
    type = string
    sensitive = false
}
variable "ENVIRONMENT" {
    default = "dev"
    type = string
    sensitive = false
}

##############################
###local file vars for gcs####
##############################
variable "INGEST_CONFIG_SOURCE_PATH" {
    type = string
    sensitive = true
    description = "local file reference to upload for ingest configuration json file"
}
variable "INGEST_CODE_SOURCE_DIR" {
    type = string
    sensitive = true
    description = "local directory for terraform to create a zip file of"
}
variable "INGEST_CODE_SOURCE_ZIP" {
    type = string
    sensitive = true
    description = "the terraform created zip file path for upload to GCS"
}
##############################
###cloud function env vars####
##############################
variable "INGEST_CONFIG_FILE_PATH" {
    default = "ingest/config.json"
    type = string
    sensitive = false
    description = "full GCS key to upload config json file"
}
variable "INGEST_CODE_ZIP_PATH" {
    default = "ingest/CfCode.zip"
    type = string
    sensitive = false
    description = "GCS key directory to use for cloud function code. Zip file name is appended to this as it is dynamic to trigger source code updates."
}
variable "REDDIT_INGEST_DATA_PATH" {
    default = "ingest/reddit/"
    sensitive = false
    description = "GCS key for reddit .tsv uploads by CF. Is a daily key."
}
variable "SPOTIFY_INGEST_DATA_PATH" {
    default = "ingest/spotify/"
    sensitive = false
    description = "GCS key for spotify .tsv uploads by CF. Is a daily key."
}
##############################
######secrets for apps########
##############################
variable "SPOTIFY_SECRET" {
    default = "spotify-ingest-api-access"
    sensitive = true
    description = "secret name to access spotify keys"
}
variable "REDDIT_SECRET" {
    default = "reddit-ingest-api-access"
    sensitive = true
    description = "secret name to access reddit keys"
}
##############################
######BigQuery Resource#######
##############################
variable "BQ_EXTRACT_SCHEMA" {
    default = "extract"
    description = "schema name to use for extract external tables"
}
