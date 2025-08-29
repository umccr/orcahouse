module "athena" {
  source = "../common/db_user"

  rotation_app_name = "OrcaVaultRDSSecretRotationAthena"
  db_user_ssm_parameter = "/orcahouse/orcavault/athena_username"  # create and set this ssm param via AWS Console UI
  secret_name = "orcahouse/orcavault/athena"  # pragma: allowlist secret
}
