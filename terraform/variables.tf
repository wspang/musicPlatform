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
###cloud function env vars####
##############################
variable "INGEST_CONFIG_FILE_PATH" {
    default = "ingest/config.json"
    type = string
    sensitive = false
}
variable "INGEST_CODE_ZIP_PATH" {
    default = "ingest/cloudFunctionCode.zip"
    type = string
    sensitive = false
}
variable "INGEST_CONFIG_SOURCE_PATH" {
    type = string
    sensitive = true
}
variable "INGEST_CODE_SOURCE_PATH" {
    type = string
    sensitive = true
}
variable "REDDIT_INGEST_DATA_PATH" {
    default = "ingest/reddit/{DATEPATH}.tsv"
    sensitive = false
}
variable "SPOTIFY_INGEST_DATA_PATH" {
    default = "ingest/spotify/{DATEPATH}.tsv"
    sensitive = false
}
