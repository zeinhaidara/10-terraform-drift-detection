terraform {
  required_version = ">= 1.5.0"
}

# terraform_data has no real backend; it just stores whatever input we give it.
# That lets the plan diff behave like real drift without touching any cloud account.
resource "terraform_data" "app_config" {
  input = {
    environment = "staging"
    replicas    = 2
  }
}

resource "terraform_data" "feature_flags" {
  input = {
    new_checkout = false
  }
}
