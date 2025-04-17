module "psa_rw" {
  source = "../common/db_user"

  rotation_app_name = "OrcaVaultRDSSecretRotationPSA"
  db_user_ssm_parameter = "/orcahouse/orcavault/psa_username"
  secret_name = "orcahouse/orcavault/psa_rw"  # pragma: allowlist secret
}
