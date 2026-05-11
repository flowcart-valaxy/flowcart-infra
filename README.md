# flowcart-infra

Infrastructure-as-Code for the flowcart platform. This repo contains all Terraform that builds AWS infrastructure across 5 accounts and 3 environments.

## Layout

```
flowcart-infra/
├── bootstrap/                    # Day 1 — AWS Org foundation
│                                 #  SCPs, CloudTrail, state bucket
├── shared/                       # Day 2+ — Shared Services account
│   ├── ecr/                      #  ECR repos for all microservices
│   ├── route53/                  #  DNS zones
│   ├── github-oidc/              #  GitHub Actions OIDC provider
│   └── kms/                      #  Cross-account KMS keys
└── environments/
    ├── dev/
    │   ├── infrastructure/       #  VPC, RDS, Redis, SQS
    │   ├── eks/                  #  EKS cluster + Karpenter
    │   └── eks-observability/    #  Prometheus, Loki, Tempo
    ├── staging/...               #  Same layout as dev
    └── prod/...                  #  Same layout as dev
```

## State

ALL Terraform state lives in one S3 bucket: `flowcart-tfstate-shared-596451157598` (in Shared Services account).

State paths follow the directory layout:
- `bootstrap/` → `shared/bootstrap/terraform.tfstate`
- `shared/ecr/` → `shared/ecr/terraform.tfstate`
- `environments/dev/eks/` → `dev/eks/terraform.tfstate`
- etc.

## Pre-flight

You need (one-time setup):

- AWS Organizations + 5 accounts (Management, Shared Services, Dev, Staging, Prod) — manual setup
- Local AWS profiles for all 5 accounts (`flowcart`, `flowcart-shared`, `flowcart-dev`, `flowcart-staging`, `flowcart-prod`)
- Terraform 1.13+
- An IAM admin user (`terraform-admin`) in Management with access keys

See `bootstrap/README.md` for the Day 1 walkthrough.

## Conventions

- All resource names use the `flowcart-` prefix
- Region: us-east-1
- All buckets are encrypted, versioned, public-access-blocked
- All resources tagged: `Project=flowcart`, `ManagedBy=Terraform`, `Layer=<layer-name>`
