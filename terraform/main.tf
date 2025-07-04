terraform {
  required_version = ">= 1.6"
  required_providers {
    aws       = { source = "hashicorp/aws",       version = "~> 5.0" }
    snowflake = { source = "Snowflake-Labs/snowflake", version = "~> 0.75" }
  }
}

provider "aws" {
  region = "eu-west-1"
}

provider "snowflake" {
  account           = var.snowflake_account
  username          = var.snowflake_user
  private_key_path  = var.snowflake_private_key_path
}

# TODO: module wiring
# module "firehose" {
#   source = "./modules/firehose"
#   stream_name = "podcast_events"
#   s3_bucket   = module.s3.bucket_name
# }

# module "s3" {
#   source = "./modules/s3"
#   bucket_name = "podcast-raw-events"
# }

# module "snowpipe" {
#   source = "./modules/snowpipe"
#   stage_name = "raw_stage"
#   pattern    = "raw_events/.*[.]jsonl$"
# }

# module "warehouse" {
#   source = "./modules/snowflake_warehouse"
#   name  = "ANALYTICS_XS"
#   size  = "XSMALL"
# } 