##############################
# set GCP as provider and run defaults if not specified on resources.
##############################

provider "google" {
    project = var.PROJECT
    region = var.REGION
    zone = var.ZONE
}

##############################
# App Engine: only one per project, region gets locked
# needed for scheduler, may come in use later too
##############################

resource "google_app_engine_application" "app_engine" {
  project     = google_project.my_project.project_id
  location_id = var.REGION 
}

##############################
# GCS Buckets: code and data bucket 
##############################

resource "google_storage_bucket" "music_code_bucket"{
    name          = format("%s-%s-%s-code",var.PROJECT,var.REGION,var.ENVIRONMENT)
    location      = var.REGION
    storage_class = "Standard"
    uniform_bucket_level_access = true
    force_destroy = false
}

resource "google_storage_bucket" "music_data_bucket"{
    name          = format("%s-%s-%s-data",var.PROJECT,var.REGION,var.ENVIRONMENT)
    location      = var.REGION
    storage_class = "Standard"
    uniform_bucket_level_access = true
    force_destroy = false
    lifecycle_rule {
        condition {
            age = 365
        }
        action {
          type = "Delete"
        }
    }
}

##############################
# Pubsub Topic and Cloud Scheduler to trigger jobs, pass data 
##############################
resource "google_pubsub_topic" "ingest_kick_off_topic" {
    name = "ingest-kick-off-topic"
}

resource "google_cloud_scheduler_job" "ingest_scheduler" {
    name        = "ingest-trigger-job"
    description = "CRON schedule to trigger the config job."
    schedule    = "0 1 * * *"

    pubsub_target {
        topic_name = google_pubsub_topic.ingest_kick_off_topic.id
        data       = base64encode("SEND IT")
  }
}

resource "google_pubsub_topic" "reddit_ingest_config_topic" {
    name = "reddit-ingest-config-topic" 
}

resource "google_pubsub_topic" "spotify_ingest_trigger_topic" {
    name = "spotify-ingest-trigger-topic"
}

##############################
# Cloud Functions for ingest. Include code zip file and function configs
##############################

resource "google_storage_bucket_object" "ingest_config_json" {
    name = var.INGEST_CONFIG_FILE_PATH
    bucket = google_storage_bucket.music_code_bucket.name
    source = var.INGEST_CONFIG_SOURCE_PATH
}

resource "google_storage_bucket_object" "cloud_function_ingest_code_zip_file" {
    name = var.INGEST_CODE_ZIP_PATH
    bucket = google_storage_bucket.music_code_bucket.name
    source = var.INGEST_CODE_SOURCE_PATH
}

resource "google_cloudfunctions_function" "ingest_config_function" {
    name = "ingest-config-function"
    description = "provides the config for the music ingest application. trigger reddit function next, then spotify"
    runtime = "python37"

    available_memory_mb = 128
    timeout = 60
    entry_point = "config_handler"
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    event_trigger {
        event_type = "google.pubsub.topic.publish"
        resource = google_pubsub_topic.ingest_kick_off_topic.id
    }
    
    source_archive_bucket = google_storage_bucket.music_code_bucket.name
    source_archive_object = google_storage_bucket_object.cloud_function_ingest_code_zip_file.name
    environment_variables = {
        CODE_BUCKET = google_storage_bucket.music_code_bucket.name
        CONFIG_FILE_PATH = google_storage_bucket_object.ingest_config_json.name
    }
}

resource "google_cloudfunctions_function" "ingest_reddit_function" {
    name = "ingest-reddit-function"
    description = "triggered from config function. uses praw to scrape reddit and load subreddit info to GCS"
    runtime = "python37"

    available_memory_mb = 256
    timeout = 300
    entry_point = "reddit_handler"
    ingress_settings = "ALLOW_ALL"
    event_trigger {
        event_type = "google.pubsub.topic.publish"
        resource = google_pubsub_topic.reddit_ingest_config_topic.id
    }
    
    source_archive_bucket = google_storage_bucket.music_code_bucket.name
    source_archive_object = google_storage_bucket_object.cloud_function_ingest_code_zip_file.name
    environment_variables = {
        DATA_BUCKET = google_storage_bucket.music_data_bucket.name
        REDDIT_INGEST_DATA_PATH = replace(var.REDDIT_INGEST_DATA_PATH, "{DATEPATH}", formatdate("YYYY/MM/DD", timestamp()))
        EXTERNAL_APP_SECRET_NAME = "reddit-api-ingest" 
        EXTERNAL_APP_SECRET_VERSION = 1
        PUBSUB_TOPIC = google_pubsub_topic.reddit_ingest_config_topic.name
    }
}

resource "google_cloudfunctions_function" "ingest_spotify_function" {
    name = "ingest-spotify-function"
    description = "Triggered from GCS upload on Reddit function. Reads the reddit scraped info from GCS csv and calls for Spotify info. reupload to GCS"
    runtime = "python37"

    available_memory_mb = 256
    timeout = 300
    entry_point = "spotify_handler"
    ingress_settings = "ALLOW_ALL"
    event_trigger {
        event_type = "google.pubsub.topic.publish"
        resource = google_pubsub_topic.spotify_ingest_trigger_topic.id
    }
    
    source_archive_bucket = google_storage_bucket.music_code_bucket.name
    source_archive_object = google_storage_bucket_object.cloud_function_ingest_code_zip_file.name
    environment_variables = {
        DATA_BUCKET = google_storage_bucket.music_data_bucket.name
        REDDIT_INGEST_DATA_PATH = replace(var.REDDIT_INGEST_DATA_PATH, "{DATEPATH}", formatdate("YYYY/MM/DD", timestamp()))
        SPOTIFY_INGEST_DATA_PATH = replace(var.SPOTIFY_INGEST_DATA_PATH, "{DATEPATH}", formatdate("YYYY/MM/DD", timestamp()))
        EXTERNAL_APP_SECRET_NAME = "spotify-api-ingest" 
        EXTERNAL_APP_SECRET_VERSION = 1
        PUBSUB_TOPIC = google_pubsub_topic.spotify_ingest_trigger_topic.name
    }
}
