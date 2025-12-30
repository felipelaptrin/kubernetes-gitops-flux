# Kubernetes Bootstrap Flux

## How to run the project

1) Install dependencies with [Mise](https://mise.jdx.dev/)

```sh
mise install
```

2) Adjust backend and vars file in `config/dev/us-east-1/ folder

3) Export AWS credentials related to the account you would like to deploy

4) Initialize Terraform

```sh
cd src/
terraform init -backend-config=../config/dev/us-east-1/backend.hcl
```

5) Deploy initial infrastructure

```sh
terraform apply -var-file="../config/dev/us-east-1/vars.tfvars" \
  -target=module.vpc \
  -target=module.eks
```

:warning: In theory, the bootstrap infrastructure should be the VPC + EKS only, but we can also add Authentik’s RDS (`-target=module.sg_authentik_db -target=module.db_authentik`) since the EKS deployment takes as much time as the RDS deployment, i.e., the deployment can be done in parallel.

6) Deploy the rest of the infrastructure

```sh
aws eks update-kubeconfig --region us-east-1 --name kubernetes-bootstrap-flux
terraform apply -var-file="../config/dev/us-east-1/vars.tfvars"
```

:warning: Since we use [flux_bootstrap_git](https://registry.terraform.io/providers/fluxcd/flux/latest/docs/resources/bootstrap_git) Terraform resource to bootstrap Flux you need to export your GitHub PAT.

7) Deploy Authentik configuration

```sh
cd apps
terraform init -backend-config=../../config/dev/us-east-1/backend_apps.hcl
terraform apply -var-file="../../config/dev/us-east-1/vars_apps.tfvars"
```