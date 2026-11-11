package com.acme.modres.util;

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
 * supplied through an environment variable (never the secret value itself).
 * Values are cached for a short period so that rotated secrets are picked up
 * automatically without restarting the application.
 */
public final class SecretsManagerHelper {

  private static final Logger logger = Logger.getLogger(SecretsManagerHelper.class.getName());

  private static final long CACHE_TTL_MS = Long
      .parseLong(System.getenv().getOrDefault("SECRETS_CACHE_TTL_MS", "300000"));

  private static volatile SecretsManagerClient client;

  private static final Object LOCK = new Object();
  private static String cachedSecretId;
  private static String cachedValue;
  private static long cachedAt;

  private SecretsManagerHelper() {
  }

  private static SecretsManagerClient getClient() {
    if (client == null) {
      synchronized (LOCK) {
        if (client == null) {
          // Region and credentials are resolved from the default AWS provider chains
          // (IAM role, AWS_REGION, etc.)
          client = SecretsManagerClient.create();
        }
      }
    }
    return client;
  }

  /**
   * Returns the secret value for the given secret id. If the secret is a JSON
   * document, the value of {@code jsonKey} is returned; otherwise the raw secret
   * string is returned. Returns null if the secret cannot be retrieved.
   */
  public static String getSecret(String secretId, String jsonKey) {
    if (secretId == null || secretId.trim().isEmpty()) {
      return null;
    }
    synchronized (LOCK) {
      long now = System.currentTimeMillis();
      if (secretId.equals(cachedSecretId) && cachedValue != null && (now - cachedAt) < CACHE_TTL_MS) {
        return cachedValue;
      }
    }
    try {
      GetSecretValueResponse resp = getClient()
          .getSecretValue(GetSecretValueRequest.builder().secretId(secretId).build());
      String value = resp.secretString();
      if (value != null && jsonKey != null) {
        try {
          JsonElement el = JsonParser.parseString(value);
          if (el.isJsonObject()) {
            JsonObject obj = el.getAsJsonObject();
            value = obj.has(jsonKey) ? obj.get(jsonKey).getAsString() : null;
          }
        } catch (RuntimeException e) {
          // not JSON - use raw secret string
        }
      }
      synchronized (LOCK) {
        cachedSecretId = secretId;
        cachedValue = value;
        cachedAt = System.currentTimeMillis();
      }
      return value;
    } catch (RuntimeException e) {
      logger.log(Level.WARNING, "Unable to retrieve secret from AWS Secrets Manager: " + e.getMessage());
      return null;
    }
  }
}
