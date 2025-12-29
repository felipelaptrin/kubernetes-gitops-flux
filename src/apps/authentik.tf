resource "authentik_property_mapping_provider_scope" "scope_email_verified_true" {
  name        = "custom email scope (email_verified=true)"
  scope_name  = "email"
  description = "Sets email_verified=true for apps that require it"
  expression  = <<-EOT
    return {
      "email": user.email,
      "email_verified": True,
    }
  EOT
}

resource "authentik_provider_oauth2" "headlamp" {
  name                = "headlamp"
  client_id           = jsondecode(data.aws_secretsmanager_secret_version.headlamp_token.secret_string)["clientID"]
  client_secret       = jsondecode(data.aws_secretsmanager_secret_version.headlamp_token.secret_string)["clientSecret"]
  signing_key         = data.authentik_certificate_key_pair.self_signed.id
  invalidation_flow   = data.authentik_flow.default_invalidation_flow.id
  authentication_flow = data.authentik_flow.default_authentication_flow.id
  authorization_flow  = data.authentik_flow.default_authorization_flow.id
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://headlamp.${var.domain}/oidc-callback",
    },
  ]
  property_mappings = [
    authentik_property_mapping_provider_scope.scope_email_verified_true.id,
    data.authentik_property_mapping_provider_scope.scope-profile.id,
    data.authentik_property_mapping_provider_scope.scope-openid.id,
  ]
  sub_mode = "user_email"
}

resource "authentik_application" "headlamp" {
  name              = "headlamp"
  slug              = "headlamp"
  protocol_provider = authentik_provider_oauth2.headlamp.id
  meta_launch_url   = "https://headlamp.${var.domain}"
  open_in_new_tab   = true
}
