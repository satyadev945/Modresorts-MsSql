package com.acme.modres.util;

import java.util.logging.Level;
import java.util.logging.Logger;

import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

/**
 * Retrieves secrets from AWS Secrets Manager. Credentials are resolved through
 * the default AWS credentials provider chain (IAM role), so no secrets are
 * stored in source code or configuration files.
 *
 * The secret name is supplied through an environment variable (name only, not
 * the secret value). Rotation is handled by Secrets Manager; values are
 * cached briefly so rotated values are picked up.
 */
public final class SecretsManagerHelper {

  private static final Logger logger = Logger.getLogger(SecretsManagerHelper.class.getName());

  private static final long CACHE_TTL_MS = 5 * 60 * 1000L;

  private static volatile String cachedName;
  private static volatile String cachedValue;
  private static volatile long cachedAt;

  private SecretsManagerHelper() {
  }

  /**
   * @param secretName name or ARN of the secret in AWS Secrets Manager
   * @return the secret string, or null if it cannot be retrieved
   */
  public static String getSecret(String secretName) {
    if (secretName == null || secretName.trim().isEmpty()) {
      return null;
    }
    long now = System.currentTimeMillis();
    if (secretName.equals(cachedName) && cachedValue != null && (now - cachedAt) < CACHE_TTL_MS) {
      return cachedValue;
    }
    String regionName = System.getenv("AWS_REGION");
    if (regionName == null || regionName.trim().isEmpty()) {
      regionName = System.getenv("AWS_DEFAULT_REGION");
    }
    try {
      software.amazon.awssdk.services.secretsmanager.SecretsManagerClientBuilder builder = SecretsManagerClient
          .builder();
      if (regionName != null && !regionName.trim().isEmpty()) {
        builder.region(Region.of(regionName));
      }
      try (SecretsManagerClient client = builder.build()) {
        GetSecretValueResponse result = client
            .getSecretValue(GetSecretValueRequest.builder().secretId(secretName).build());
        String value = result.secretString();
        cachedName = secretName;
        cachedValue = value;
        cachedAt = now;
        return value;
      }
    } catch (Exception e) {
      logger.log(Level.WARNING, "Unable to retrieve secret from AWS Secrets Manager: " + e.getMessage());
      return null;
    }
  }
}
