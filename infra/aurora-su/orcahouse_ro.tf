module "dbuser_ro" {
  source = "../common/db_user"

  rotation_app_name = "OrcaHouseRDSSecretRotationRO"
  db_user_ssm_parameter = "/orcahouse/ro_username"  # create and set this ssm param via AWS Console UI
  secret_name = "orcahouse/dbuser_ro"  # pragma: allowlist secret
}
