

output "ecr_repo_url" {
  value = aws_ecr_repository.repo.repository_url
}

output "pipeline_name" {
  value = aws_codepipeline.pipeline.name
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
