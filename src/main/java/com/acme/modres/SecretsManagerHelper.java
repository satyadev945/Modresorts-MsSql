package com.acme.modres;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.util.logging.Level;
import java.util.logging.Logger;

import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

/**
 * Retrieves application secrets from AWS Secrets Manager. The secret id is
 * supplied through an environment variable (never the secret itself). The
 * secret value may be a plain string or a JSON document containing the
 * requested key. Region and credentials are resolved by the AWS SDK default
 * provider chains (IAM role, environment, etc.).
 */
public final class SecretsManagerHelper {

  private static final Logger logger = Logger.getLogger(SecretsManagerHelper.class.getName());

  private SecretsManagerHelper() {
  }

  /**
   * @param secretIdEnvVar environment variable holding the Secrets Manager
   *                       secret name or ARN
   * @param jsonKey        key to read if the secret is a JSON document
   * @return the secret value or null when not configured / not retrievable
   */
  public static String getSecret(String secretIdEnvVar, String jsonKey) {
    String secretId = System.getenv(secretIdEnvVar);
    if (secretId == null || secretId.trim().isEmpty()) {
      return null;
    }

    try (SecretsManagerClient client = SecretsManagerClient.create()) {
      GetSecretValueResponse result = client.getSecretValue(
          GetSecretValueRequest.builder().secretId(secretId.trim()).build());
      String secret = result.secretString();
      if (secret == null) {
        return null;
      }
      String trimmed = secret.trim();
      if (trimmed.startsWith("{")) {
        JsonObject obj = JsonParser.parseString(trimmed).getAsJsonObject();
        JsonElement value = obj.get(jsonKey);
        return (value == null || value.isJsonNull()) ? null : value.getAsString();
      }
      return trimmed;
    } catch (Exception e) {
      logger.log(Level.WARNING, "Unable to retrieve secret from AWS Secrets Manager: " + e.getMessage());
      return null;
    }
  }
}
