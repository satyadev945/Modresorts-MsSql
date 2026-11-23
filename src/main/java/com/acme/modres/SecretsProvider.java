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
 * Retrieves application secrets from AWS Secrets Manager.
 *
 * The secret name/ARN is supplied through the WEATHER_API_SECRET_ID environment
 * variable (no secret values are stored in code or property files). The secret
 * may be either a plain string or a JSON document containing the key
 * "WEATHER_API_KEY". The AWS region and credentials are resolved by the AWS SDK
 * default provider chains (IAM role, AWS_REGION, etc.).
 *
 * Secrets are re-fetched after a short TTL so that rotated values are picked up
 * without restarting the application.
 */
public final class SecretsProvider {

  private static final Logger logger = Logger.getLogger(SecretsProvider.class.getName());

  public static final String WEATHER_API_SECRET_ID_ENV = "WEATHER_API_SECRET_ID";
  public static final String WEATHER_API_KEY_FIELD = "WEATHER_API_KEY";

  private static final long CACHE_TTL_MS = 5 * 60 * 1000L;

  private static volatile String cachedWeatherApiKey;
  private static volatile long cachedAt = 0L;

  private SecretsProvider() {
  }

  /**
   * Returns the weather API key from AWS Secrets Manager, or null if no secret
   * is configured / available.
   */
  public static String getWeatherApiKey() {
    String secretId = System.getenv(WEATHER_API_SECRET_ID_ENV);
    if (secretId == null || secretId.trim().isEmpty()) {
      logger.log(Level.FINE, WEATHER_API_SECRET_ID_ENV + " is not set; weather API key not configured.");
      return null;
    }

    long now = System.currentTimeMillis();
    String cached = cachedWeatherApiKey;
    if (cached != null && (now - cachedAt) < CACHE_TTL_MS) {
      return cached;
    }

    try (SecretsManagerClient client = SecretsManagerClient.create()) {
      GetSecretValueResponse result = client
          .getSecretValue(GetSecretValueRequest.builder().secretId(secretId.trim()).build());
      String secretString = result.secretString();
      String apiKey = extractKey(secretString);
      cachedWeatherApiKey = apiKey;
      cachedAt = now;
      return apiKey;
    } catch (Exception e) {
      logger.log(Level.WARNING, "Unable to retrieve weather API key from AWS Secrets Manager: " + e.getMessage());
      return cached;
    }
  }

  private static String extractKey(String secretString) {
    if (secretString == null) {
      return null;
    }
    String trimmed = secretString.trim();
    if (trimmed.startsWith("{")) {
      try {
        JsonObject json = JsonParser.parseString(trimmed).getAsJsonObject();
        JsonElement value = json.get(WEATHER_API_KEY_FIELD);
        return (value == null || value.isJsonNull()) ? null : value.getAsString();
      } catch (RuntimeException e) {
        logger.log(Level.WARNING, "Secret is not valid JSON; using raw secret string.");
      }
    }
    return trimmed;
  }
}
