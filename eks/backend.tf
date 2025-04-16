terraform {
  required_version = ">= 1.8.4, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.49.0"
    }

    helm = {
       source  = "hashicorp/helm"
       version = "= 2.5.1"
    }
  }

  backend "s3" {
    bucket         = "eks-backend-state-bucket"
    region         = "us-east-1"
    key            = "eks/terraform.tfstate"
    dynamodb_table = "Lock_Files"
    encrypt        = true
  }


}

provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
