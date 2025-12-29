data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

data "authentik_flow" "default_authentication_flow" {
  slug = "default-authentication-flow"
}

data "authentik_property_mapping_provider_scope" "scope-email" {
  name = "authentik default OAuth Mapping: OpenID 'email'"
}

data "authentik_property_mapping_provider_scope" "scope-profile" {
  name = "authentik default OAuth Mapping: OpenID 'profile'"
}

data "authentik_property_mapping_provider_scope" "scope-openid" {
  name = "authentik default OAuth Mapping: OpenID 'openid'"
}

data "authentik_certificate_key_pair" "self_signed" {
  name = "authentik Self-signed Certificate"
}

#################################
##### AWS - AUTHENTIK
##############################
data "aws_secretsmanager_secret" "authentik_token" {
  name = "${var.environment}/k8s/authentik"
}

data "aws_secretsmanager_secret_version" "authentik_token" {
  secret_id = data.aws_secretsmanager_secret.authentik_token.id
}

#################################
##### AWS - HEADLAMP
##############################
data "aws_secretsmanager_secret" "headlamp_token" {
  name = "${var.environment}/k8s/headlamp"
}

data "aws_secretsmanager_secret_version" "headlamp_token" {
  secret_id = data.aws_secretsmanager_secret.headlamp_token.id
}
