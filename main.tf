terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws    = { source = "hashicorp/aws",    version = ">= 5.40.0" }
    random = { source = "hashicorp/random", version = ">= 3.6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

########################
# Locals (EDIT THESE)
########################
locals {
  name                  = "case6-cicd"
  ecr_name              = "case6-ecr"
  branch_name           = "main"              # <- use main
  eks_cluster           = "demo-eks-cluster"
  k8s_namespace         = "default"
  deployment_name       = "webapp"

  # --- CHANGE ME ---
  github_repo_fullname  = "awsterraworkshop/case6-buildfiles"   # e.g., talktotechie/case6-demo
  github_connection_arn = "arn:aws:codeconnections:us-east-1:777669575376:connection/e4f2c3ec-7fc6-48f3-b622-3973907b18ed"
}

########################
# S3 artifact bucket (SSE-S3)
########################
resource "random_id" "rand" { byte_length = 3 }

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name}-artifacts-${random_id.rand.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

########################
# ECR repository
########################
resource "aws_ecr_repository" "repo" {
  name                 = local.ecr_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

data "aws_caller_identity" "current" {}

########################
# CloudWatch Log Groups (explicit, neat)
########################
resource "aws_cloudwatch_log_group" "cb_build"  { 
  name = "/codebuild/${local.name}-build"  
  retention_in_days = 14 
}
resource "aws_cloudwatch_log_group" "cb_deploy" { 
  name = "/codebuild/${local.name}-deploy"  
  retention_in_days = 14 
}

########################
# IAM for CodeBuild
########################
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
      type = "Service"
      identifiers = ["codebuild.amazonaws.com"] 
    }
  }
}
resource "aws_iam_role" "codebuild" {
  name               = "${local.name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

    
########################
# IAM for CodePipeline
########################
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
      type = "Service"
      identifiers = ["codepipeline.amazonaws.com"] 
      }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${local.name}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
}

resource "aws_iam_role_policy_attachment" "codepipeline_inline" {
  role       = aws_iam_role.codepipeline.id
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

########################
# CodeBuild Projects
########################
resource "aws_codebuild_project" "build" {
  name          = "${local.name}-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # Docker build
    environment_variable { 
      name = "AWS_REGION"   
      value = "us-east-1" 
    }
    environment_variable { 
      name  = "ECR_REPO_URI" 
      value = aws_ecr_repository.repo.repository_url 
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-build.yml"   # this file lives in your GitHub repo
  }

  logs_config { 
    cloudwatch_logs { 
      group_name = aws_cloudwatch_log_group.cb_build.name  
      stream_name = "build" 
      } 
    }
}

resource "aws_codebuild_project" "deploy" {
  name          = "${local.name}-deploy"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
    environment_variable { 
      name = "AWS_REGION"       
      value = "us-east-1" 
    }
    environment_variable { 
      name  = "EKS_CLUSTER_NAME" 
      value = local.eks_cluster 
    }
    environment_variable { 
      name  = "K8S_NAMESPACE"    
      value = local.k8s_namespace 
    }
    environment_variable { 
      name  = "DEPLOYMENT_NAME"  
      value = local.deployment_name 
    }
    environment_variable { 
      name  = "ECR_REPO_URI"     
      value = aws_ecr_repository.repo.repository_url 
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-deploy.yml"  # this file lives in your GitHub repo
  }

  logs_config { 
    cloudwatch_logs { 
      group_name = aws_cloudwatch_log_group.cb_deploy.name 
      stream_name = "deploy" 
      } 
    }
}

########################
# CodePipeline (Source = GitHub via CodeConnections)
########################
resource "aws_codepipeline" "pipeline" {
  name     = "${local.name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = local.github_connection_arn
        FullRepositoryId = local.github_repo_fullname   # org/repo
        BranchName       = local.branch_name            # main
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build_Image"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration    = { ProjectName = aws_codebuild_project.build.name }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy_to_EKS"
      category        = "Build"     # using CodeBuild to deploy
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["build_output"]
      version         = "1"
      configuration   = { ProjectName = aws_codebuild_project.deploy.name }
    }
  }
}

resource "aws_eks_access_entry" "cb" {
  cluster_name  = local.eks_cluster
  principal_arn = aws_iam_role.codebuild.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cb_admin" {
  cluster_name  = local.eks_cluster
  principal_arn = aws_eks_access_entry.cb.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type        = "namespace"
    namespaces  = ["default"]
  }
}