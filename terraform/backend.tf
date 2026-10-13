terraform {
  backend "s3" {
    bucket       = "srivi24-terraform-state-2026"
    key          = "blue-green/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}