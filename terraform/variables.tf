variable "project_id" {
  description = "The GCP Project ID"
  type        = string
  default     = "project-983494c7-6c70-4696-a77"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "db_password" {
  description = "Password for the Postgres database"
  type        = string
  sensitive   = true
  default     = "Password123"
}

variable "gcs_bucket_name" {
  description = "Unique name for the GCS bucket"
  type        = string
  default     = "hybrid-gcs-bucket"
}

variable "s3_bucket_name" {
  description = "LocalStack S3 bucket name"
  type        = string
  default     = "localstack-s3-bucket"
}

variable "sqs_queue_name" {
  description = "LocalStack SQS queue name"
  type        = string
  default     = "localstack-sqs-queue"
}

variable "lambda_function_name" {
  description = "LocalStack Lambda function name"
  type        = string
  default     = "localstack-lambda"
}