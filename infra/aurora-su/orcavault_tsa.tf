module "tsa_rw" {
  source = "../common/db_user"

  rotation_app_name = "OrcaVaultRDSSecretRotationTSA"
  db_user_ssm_parameter = "/orcahouse/orcavault/tsa_username"  # create and set this ssm param via AWS Console UI
  secret_name = "orcahouse/orcavault/tsa_rw"  # pragma: allowlist secret
}
