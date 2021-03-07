##############################
# set GCP as provider and run defaults if not specified on resources.
##############################

provider "google" {
    project = var.PROJECT
    region = var.REGION
    zone = var.ZONE
}

##############################
# GCS Buckets: code and data bucket 
##############################

resource "google_storage_bucket" "music_code_bucket"{
    name          = format("%s-%s-code",var.PROJECT,var.REGION)
    location      = var.REGION
    storage_class = "STANDARD"
    uniform_bucket_level_access = true
    force_destroy = false
}

# roles/storage.objectViewer does not include get bucket access. need below or a custom role.
resource "google_storage_bucket_iam_member" "code_bucket_cf_ingest_member" {
    bucket = google_storage_bucket.music_code_bucket.name
    role = "roles/storage.legacyBucketReader"
    member = "serviceAccount:${google_service_account.cloudfunction_service_account.email}"
    depends_on = [time_sleep.iam_sa_delay]
}

resource "google_storage_bucket_iam_member" "code_object_cf_ingest_member" {
    bucket = google_storage_bucket.music_code_bucket.name
    role = "roles/storage.objectViewer"
    member = "serviceAccount:${google_service_account.cloudfunction_service_account.email}"
    condition {
        title = "cf_ingest_code_bucket_access"
        description = "allow cloud functions to get config ingest files"
        expression = "resource.type == 'storage.googleapis.com/Object' && resource.name == 'projects/_/buckets/${google_storage_bucket.music_code_bucket.name}/objects/${var.INGEST_CONFIG_FILE_PATH}'" 
        expression = <<-EOT
            resource.type == 'storage.googleapis.com/Bucket' 
            || ( resource.type == 'storage.googleapis.com/Object' 
                && resource.name == 'projects/_/buckets/${google_storage_bucket.music_data_bucket.name}/objects/${var.INGEST_CONFIG_FILE_PATH}' )
            EOT
    } 
    depends_on = [time_sleep.iam_sa_delay]
}

resource "google_storage_bucket" "music_data_bucket"{
    name          = format("%s-%s-data",var.PROJECT,var.REGION)
    location      = var.REGION
    storage_class = "STANDARD"
    uniform_bucket_level_access = true
    force_destroy = false
    lifecycle_rule {
        condition {age = 730}
        action {type = "Delete"}
    }
}

resource "google_storage_bucket_iam_member" "data_bucket_cf_ingest_member" {
    bucket = google_storage_bucket.music_data_bucket.name
    role = "roles/storage.legacyBucketReader"
    member = "serviceAccount:${google_service_account.cloudfunction_service_account.email}"
    depends_on = [time_sleep.iam_sa_delay]
}

resource "google_storage_bucket_iam_member" "data_object_cf_ingest_member" {
    bucket = google_storage_bucket.music_data_bucket.name
    role = "roles/storage.objectAdmin"
    member = "serviceAccount:${google_service_account.cloudfunction_service_account.email}"
    condition {
        title = "cf_ingest_data_object_access"
        description = "allow cloud functions to get and put data files for ingest"
        expression = <<-EOT
            resource.type == 'storage.googleapis.com/Bucket' 
            || ( resource.type == 'storage.googleapis.com/Object' 
                && ( resource.name.startsWith( 'projects/_/buckets/${google_storage_bucket.music_data_bucket.name}/objects/${var.REDDIT_INGEST_DATA_PATH}' ) 
                    || resource.name.startsWith( 'projects/_/buckets/${google_storage_bucket.music_data_bucket.name}/objects/${var.SPOTIFY_INGEST_DATA_PATH}' )))
            EOT
    } 
    depends_on = [time_sleep.iam_sa_delay]
}

##############################
# GCS Objects for Cloud Functions. 
##############################

resource "google_storage_bucket_object" "ingest_config_json" {
    name = var.INGEST_CONFIG_FILE_PATH
    bucket = google_storage_bucket.music_code_bucket.name
    source = var.INGEST_CONFIG_SOURCE_PATH
}

data "archive_file" "cloud_function_source_code" {
    type= "zip"
    source_dir = var.INGEST_CODE_SOURCE_DIR
    output_path = var.INGEST_CODE_SOURCE_ZIP 
}

resource "google_storage_bucket_object" "cloud_function_ingest_code_zip_file" {
    bucket = google_storage_bucket.music_code_bucket.name
    name = "${var.INGEST_CODE_ZIP_PATH}#${data.archive_file.cloud_function_source_code.output_md5}"
    source = data.archive_file.cloud_function_source_code.output_path
    content_disposition = "attachment"
    content_encoding = "gzip"
    content_type = "application/zip"
}

##############################
# Service Account for Cloud Functions
##############################

resource "google_service_account" "cloudfunction_service_account" {
    account_id = "cf-ingest-sa-limited-69"
    display_name = "CF_SA"
    description = "limited permissions for cloud functions to do they ingest."
}

resource "time_sleep" "iam_sa_delay" {
    # allow delay in SA creation for eventual consistency
    create_duration = "4m"
    triggers = {
        google_service_account = google_service_account.cloudfunction_service_account.id
    }
}

##############################
# Pubsub Topic and Cloud Scheduler to trigger jobs, pass data 
##############################
resource "google_cloud_scheduler_job" "ingest_scheduler" {
    name        = "ingest-trigger-job"
    description = "CRON schedule to trigger the config job."
    schedule    = "0 1 * * *"

    pubsub_target {
        topic_name = google_pubsub_topic.ingest_kick_off_topic.id
        data       = base64encode("SEND IT")
  }
}

data "google_iam_policy" "ingest_pubsub_policy_data" {
    depends_on = [time_sleep.iam_sa_delay]
    binding {
        role = "roles/pubsub.publisher"
        members = ["serviceAccount:${google_service_account.cloudfunction_service_account.email}", "serviceAccount:${var.PROJECT}@appspot.gserviceaccount.com"]
    }
    binding {
        role = "roles/pubsub.subscriber"
        members = ["serviceAccount:${google_service_account.cloudfunction_service_account.email}"]
    }
}

resource "google_pubsub_topic" "ingest_kick_off_topic" {
    name = "ingest-kick-off-topic"
}

resource "google_pubsub_topic_iam_policy" "ingest_pubsub_config_policy" {
    topic = google_pubsub_topic.ingest_kick_off_topic.name 
    policy_data = data.google_iam_policy.ingest_pubsub_policy_data.policy_data
}

resource "google_pubsub_topic" "reddit_ingest_config_topic" {
    name = "reddit-ingest-config-topic" 
}

resource "google_pubsub_topic_iam_policy" "ingest_pubsub_reddit_policy" {
    topic = google_pubsub_topic.reddit_ingest_config_topic.name 
    policy_data = data.google_iam_policy.ingest_pubsub_policy_data.policy_data
}
resource "google_pubsub_topic" "spotify_ingest_trigger_topic" {
    name = "spotify-ingest-trigger-topic"
}

resource "google_pubsub_topic_iam_policy" "ingest_pubsub_spotify_policy" {
    topic = google_pubsub_topic.spotify_ingest_trigger_topic.name 
    policy_data = data.google_iam_policy.ingest_pubsub_policy_data.policy_data
}

##############################
# Secret Manager for Ext. App Creds
##############################

resource "google_secret_manager_secret" "reddit_secret" {
    secret_id = var.REDDIT_SECRET
    replication {automatic = true}
}

resource "google_secret_manager_secret" "spotify_secret" {
    secret_id = var.SPOTIFY_SECRET
    replication {automatic = true}
}

data "google_iam_policy" "ingest_secret_policy_data" {
    depends_on = [time_sleep.iam_sa_delay]
    binding {
        role = "roles/secretmanager.secretAccessor"
        members = ["serviceAccount:${google_service_account.cloudfunction_service_account.email}"]
  }
}

resource "google_secret_manager_secret_iam_policy" "spotify_secret_policy" {
    secret_id = google_secret_manager_secret.spotify_secret.secret_id
    policy_data = data.google_iam_policy.ingest_secret_policy_data.policy_data
}

resource "google_secret_manager_secret_iam_policy" "reddit_secret_policy" {
    secret_id = google_secret_manager_secret.reddit_secret.secret_id
    policy_data = data.google_iam_policy.ingest_secret_policy_data.policy_data
}

##############################
# Cloud Functions for ingest. 
##############################

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
        GCP_PROJECT_ID = var.PROJECT_ID
        PUBSUB_TOPIC = google_pubsub_topic.reddit_ingest_config_topic.name
    }

    # tie service account defined above to cloud function. Time sleep to allow eventual consistency on IAM SA creation
    service_account_email = google_service_account.cloudfunction_service_account.email 
    depends_on = [time_sleep.iam_sa_delay]
}

resource "google_cloudfunctions_function" "ingest_reddit_function" {
    name = "ingest-reddit-function"
    description = "triggered from config function. uses praw to scrape reddit and load subreddit info to GCS"
    runtime = "python37"

    available_memory_mb = 256
    timeout = 300
    entry_point = "reddit_handler"
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    event_trigger {
        event_type = "google.pubsub.topic.publish"
        resource = google_pubsub_topic.reddit_ingest_config_topic.id
    }
    
    source_archive_bucket = google_storage_bucket.music_code_bucket.name
    source_archive_object = google_storage_bucket_object.cloud_function_ingest_code_zip_file.name
    environment_variables = {
        DATA_BUCKET = google_storage_bucket.music_data_bucket.name
        REDDIT_INGEST_DATA_PATH = "${var.REDDIT_INGEST_DATA_PATH}{DATEPARTITION}/data.tsv"
        EXTERNAL_APP_SECRET_NAME = var.REDDIT_SECRET 
        EXTERNAL_APP_SECRET_VERSION = "latest"
        PUBSUB_TOPIC = google_pubsub_topic.spotify_ingest_trigger_topic.name
        GCP_PROJECT_ID = var.PROJECT_ID
    }

    # tie service account defined above to cloud function. Time sleep to allow eventual consistency on IAM SA creation
    service_account_email = google_service_account.cloudfunction_service_account.email 
    depends_on = [time_sleep.iam_sa_delay]
}

resource "google_cloudfunctions_function" "ingest_spotify_function" {
    name = "ingest-spotify-function"
    description = "Triggered from GCS upload on Reddit function. Reads the reddit scraped info from GCS csv and calls for Spotify info. reupload to GCS"
    runtime = "python37"

    available_memory_mb = 256
    timeout = 300
    entry_point = "spotify_handler"
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    event_trigger {
        event_type = "google.pubsub.topic.publish"
        resource = google_pubsub_topic.spotify_ingest_trigger_topic.id
    }
    
    source_archive_bucket = google_storage_bucket.music_code_bucket.name
    source_archive_object = google_storage_bucket_object.cloud_function_ingest_code_zip_file.name
    environment_variables = {
        DATA_BUCKET = google_storage_bucket.music_data_bucket.name
        REDDIT_INGEST_DATA_PATH = "${var.REDDIT_INGEST_DATA_PATH}{DATEPARTITION}/data.tsv"
        SPOTIFY_INGEST_DATA_PATH = "${var.SPOTIFY_INGEST_DATA_PATH}{DATEPARTITION}/data.tsv"
        EXTERNAL_APP_SECRET_NAME = var.SPOTIFY_SECRET 
        EXTERNAL_APP_SECRET_VERSION = "latest"
        GCP_PROJECT_ID = var.PROJECT_ID
    }

    # tie service account defined above to cloud function. Time sleep to allow eventual consistency on IAM SA creation
    service_account_email = google_service_account.cloudfunction_service_account.email 
    depends_on = [time_sleep.iam_sa_delay]
}

##############################
# BigQuery Extract Dataset and External Tables 
##############################

resource "google_bigquery_dataset" "extract_schema" {
    dataset_id = var.BQ_EXTRACT_SCHEMA
    description = "Extract schema for external tables in GCS"
    location = "US"
    delete_contents_on_destroy = true
    default_table_expiration_ms = null
    default_partition_expiration_ms = null
    access {
        role = "OWNER"
        user_by_email = TODO
    }
}

resource "google_bigquery_table" "extract_tbl_reddit" {
    dataset_id = google_bigquery_dataset.extract_schema.dataset_id
    table_id   = "reddit"
    description = "external table on reddit GCS path"
    deletion_protection = false

    external_data_configuration {
        source_format = "CSV"
        source_uris = "${google_storage_bucket.music_data_bucket.name}${var.REDDIT_INGEST_DATA_PATH}*"
        autodetect = true
        schema = null
        compression = "NONE"
        ignore_unknown_values = true
        hive_partitioning_options {
            mode = AUTO
            source_uri_prefix = "${google_storage_bucket.music_data_bucket.name}${var.REDDIT_INGEST_DATA_PATH}"
        }
    }
}

resource "google_bigquery_table" "extract_tbl_spotify" {
    dataset_id = google_bigquery_dataset.extract_schema.dataset_id
    table_id   = "spotify"
    description = "external table on spotify GCS path"
    deletion_protection = false

    external_data_configuration {
        source_format = "CSV"
        source_uris = "${google_storage_bucket.music_data_bucket.name}${var.SPOTIFY_INGEST_DATA_PATH}*"
        autodetect = true
        schema = null
        compression = "NONE"
        ignore_unknown_values = true
        hive_partitioning_options {
            mode = AUTO
            source_uri_prefix = "${google_storage_bucket.music_data_bucket.name}${var.SPOTIFY_INGEST_DATA_PATH}"
        }
    }
}
