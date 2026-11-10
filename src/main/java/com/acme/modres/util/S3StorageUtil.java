package com.acme.modres.util;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

/**
 * Simple helper for reading/writing objects in Amazon S3 (AWS SDK for Java v2).
 * Configuration is read from environment variables:
 * <ul>
 * <li>S3_BUCKET_NAME - target bucket (required for S3 operations)</li>
 * <li>AWS_REGION - AWS region (optional, default credential/region chain is used otherwise)</li>
 * </ul>
 * Credentials are resolved through the default AWS credentials provider chain (IAM role, etc.).
 */
public final class S3StorageUtil {

  private static volatile S3Client client;

  private S3StorageUtil() {
  }

  public static String getBucketName() {
    String bucket = System.getenv("S3_BUCKET_NAME");
    return (bucket == null || bucket.trim().isEmpty()) ? null : bucket.trim();
  }

  public static boolean isConfigured() {
    return getBucketName() != null;
  }

  private static S3Client getClient() {
    if (client == null) {
      synchronized (S3StorageUtil.class) {
        if (client == null) {
          software.amazon.awssdk.services.s3.S3ClientBuilder builder = S3Client.builder();
          String region = System.getenv("AWS_REGION");
          if (region != null && !region.trim().isEmpty()) {
            builder.region(Region.of(region.trim()));
          }
          client = builder.build();
        }
      }
    }
    return client;
  }

  public static byte[] getObjectBytes(String key) throws IOException {
    GetObjectRequest request = GetObjectRequest.builder().bucket(getBucketName()).key(key).build();
    try (InputStream in = getClient().getObject(request)) {
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buf = new byte[4096];
      int n;
      while ((n = in.read(buf)) >= 0) {
        out.write(buf, 0, n);
      }
      return out.toByteArray();
    }
  }

  public static void putObject(String key, byte[] data, String contentType) {
    PutObjectRequest request = PutObjectRequest.builder().bucket(getBucketName()).key(key)
        .contentType(contentType).build();
    getClient().putObject(request, RequestBody.fromBytes(data));
  }
}
