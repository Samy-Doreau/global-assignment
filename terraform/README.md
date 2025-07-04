# Terraform Infrastructure – Quick-start

## Prerequisites

- Terraform ≥ **1.6**
- AWS CLI configured with an IAM user that can create Kinesis / S3
- Snowflake key-pair authentication – private key path exported via `TF_VAR_snowflake_private_key_path`

## Bootstrapping

```bash
cd terraform
terraform init
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

The root module wires up reusable modules found under `modules/` – one per layer.
Use separate `envs/*.tfvars` files for **dev**, **staging**, **prod** to keep secrets out of VCS.

## State management

Backed by an S3 bucket + DynamoDB lock table (configure in `backend.tf`).

## Destroy

```bash
terraform destroy -var-file=envs/dev.tfvars
```
