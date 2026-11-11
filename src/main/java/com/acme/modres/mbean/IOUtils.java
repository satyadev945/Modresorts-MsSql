package com.acme.modres.mbean;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

import com.acme.modres.mbean.reservation.ReservationList;
import com.google.gson.Gson;

import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;

/**
 * Configuration loading utilities. No local file system writes are performed:
 * configuration is streamed directly into memory either from Amazon S3 (when
 * CONFIG_S3_BUCKET is set) or from read-only classpath resources.
 * <p>
 * Any byte[] handled here is in-memory only; if binary data is ever stored in
 * PostgreSQL, use a BYTEA column with setBytes()/getBytes() (Types.BINARY).
 */
public final class IOUtils {

  private IOUtils() {
  }

  /**
   * Opens a configuration resource. Uses Amazon S3 when CONFIG_S3_BUCKET is
   * defined (optional CONFIG_S3_PREFIX), otherwise falls back to the classpath.
   */
  private static InputStream openConfigStream(String path) throws IOException {
    String bucket = System.getenv("CONFIG_S3_BUCKET");
    if (bucket != null && !bucket.trim().isEmpty()) {
      String prefix = System.getenv().getOrDefault("CONFIG_S3_PREFIX", "");
      String key = prefix + path;
      try (S3Client s3 = S3Client.create()) {
        byte[] data = s3.getObjectAsBytes(GetObjectRequest.builder().bucket(bucket).key(key).build())
            .asByteArray();
        return new java.io.ByteArrayInputStream(data);
      }
    }
    InputStream is = IOUtils.class.getClassLoader().getResourceAsStream(path);
    if (is == null) {
      throw new IOException("Configuration resource not found: " + path);
    }
    return is;
  }

  private static <T> T readJson(String path, Class<T> cls) {
    try (InputStream is = openConfigStream(path);
        BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
      return new Gson().fromJson(reader, cls);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    return readJson("ops.json", OpMetadataList.class);
  }

  public static ReservationList getReservationListFromConfig() {
    return readJson("reservations.json", ReservationList.class);
  }

}
