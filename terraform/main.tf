provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

 endpoints {
  s3     = "http://35.238.234.95:4566"
  sqs    = "http://35.238.234.95:4566"
  lambda = "http://35.238.234.95:4566"
  iam    = "http://35.238.234.95:4566"
  sts    = "http://35.238.234.95:4566"
  s3control = "http://35.238.234.95:4566"
}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  name                    = "hybrid-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "hybrid-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "postgres" {
  name                = "hybrid-postgres-instance"
  database_version    = "POSTGRES_14"
  region              = var.region
  deletion_protection = false

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "database" {
  name     = "hybrid_db"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "users" {
  name     = "hybriduser"
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}

resource "google_vpc_access_connector" "connector" {
  name          = "hybrid-connector"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.8.0.0/28"
  
  # Add these two lines to fix Error code 3
  min_instances = 2
  max_instances = 3
}
resource "google_storage_bucket" "app_bucket" {
  name          = var.gcs_bucket_name
  location      = var.region
  force_destroy = true
}

resource "google_service_account" "cloudrun_sa" {
  account_id   = "hybrid-cloudrun-sa"
  display_name = "Hybrid Cloud Run Service Account"
}

resource "google_project_iam_member" "cloudrun_storage_access" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

resource "google_project_iam_member" "cloudrun_sql_access" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

resource "google_cloud_run_service" "app" {
  name     = "hybrid-app"
  location = var.region

  depends_on = [
    google_sql_database_instance.postgres,
    google_service_account.cloudrun_sa
  ]

  template {
    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector.id
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }

    spec {
      service_account_name = google_service_account.cloudrun_sa.email

      containers {
        image = "gcr.io/${var.project_id}/hybrid-app:v3"

        env {
          name  = "DB_HOST"
          value = google_sql_database_instance.postgres.private_ip_address
        }

        env {
          name  = "DB_USER"
          value = google_sql_user.users.name
        }

        env {
          name  = "DB_PASSWORD"
          value = var.db_password
        }

       env {
  name  = "AWS_ENDPOINT_URL"
  value = "http://35.238.234.95:4566"
}

env {
  name  = "SQS_QUEUE_URL"
  value = "http://35.238.234.95:4566/000000000000/localstack-sqs-queue"
}

        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.app_bucket.name
        }

        env {
          name  = "LOCALSTACK_S3_BUCKET"
          value = var.s3_bucket_name
        }
      }
    }
  }
}

resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_service.app.name
  location = google_cloud_run_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "aws_s3_bucket" "localstack_bucket" {
  bucket        = var.s3_bucket_name
  force_destroy = true
}

resource "aws_sqs_queue" "localstack_queue" {
  name = var.sqs_queue_name
}

resource "aws_iam_role" "lambda_role" {
  name = "localstack-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_lambda_function" "localstack_lambda" {
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_role.arn
  filename         = "${path.module}/../lambda/function.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/function.zip")
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.localstack_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.localstack_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_function.localstack_lambda]
}

resource "google_monitoring_dashboard" "cloudrun_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Hybrid Cloud Run Monitoring Dashboard"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Cloud Run Request Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.\"service_name\"=\"hybrid-app\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Cloud Run P99 Request Latency"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\" resource.label.\"service_name\"=\"hybrid-app\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_PERCENTILE_99"
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}

output "cloud_run_url" {
  value = google_cloud_run_service.app.status[0].url
}