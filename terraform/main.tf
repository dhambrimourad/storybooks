terraform {
  backend "gcs" {
    bucket = "devops-mourad-terraform"
    prefix = "/state/storybooks"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 3.38"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 2.0"
    }
  }
}
