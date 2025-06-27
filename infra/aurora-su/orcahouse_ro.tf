module "dbuser_ro" {
  source = "../common/db_user"

  rotation_app_name = "OrcaHouseRDSSecretRotationRO"
  db_user_ssm_parameter = "/orcahouse/ro_username"
  secret_name = "orcahouse/dbuser_ro"  # pragma: allowlist secret
}
