## Proposed Terraform repo skeleton

```text
terraform/
├── main.tf            # providers + root module calls
├── envs/
│   └── dev.tfvars     # per-environment variables
├── modules/
│   ├── firehose/
│   │   ├── main.tf
│   │   └── variables.tf
│   ├── s3/
│   │   ├── main.tf
│   │   └── variables.tf
│   ├── snowpipe/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── snowflake_warehouse/
│       ├── main.tf
│       └── variables.tf
└── README.md
```

### Module overview

- **firehose/** – creates `aws_kinesis_firehose_delivery_stream`, IAM role, CloudWatch DLQ. Variables: `stream_name`, `s3_bucket`, `buffer_interval`. Outputs: `firehose_arn`.
- **s3/** – raw bucket with versioning & lifecycle. Variables: `bucket_name`, `expiry_days`.
- **snowpipe/** – `aws_s3_bucket_notification` + `snowflake_pipe`. Variables: `stage_name`, `pattern`. Outputs: `pipe_name`.
- **snowflake_warehouse/** – warehouse + database & schema skeleton. Variables: `name`, `size`, `auto_suspend`. Outputs: `warehouse_name`.

Each module is self-contained; root `main.tf` wires them together, passing ARNs & names via outputs → inputs.
