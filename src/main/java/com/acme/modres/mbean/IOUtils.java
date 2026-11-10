package com.acme.modres.mbean;

import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;

import com.acme.modres.mbean.reservation.ReservationList;
import com.acme.modres.util.S3StorageUtil;
import com.google.gson.Gson;

public final class IOUtils {

  /**
   * Reads a configuration resource fully into memory. When S3_BUCKET_NAME is set the
   * object is read from Amazon S3; otherwise the bundled classpath resource is used.
   * No local file system writes (e.g. temp files) are performed.
   */
  public static byte[] getResourceBytes(String path) throws IOException {
    if (S3StorageUtil.isConfigured()) {
      try {
        return S3StorageUtil.getObjectBytes(path);
      } catch (RuntimeException e) {
        // fall back to the bundled classpath resource if the object is not available in S3
        e.printStackTrace();
      }
    }
    try (InputStream is = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (is == null) {
        throw new FileNotFoundException(path);
      }
      ByteArrayOutputStream buffer = new ByteArrayOutputStream();
      byte[] chunk = new byte[4096];
      int read;
      while ((read = is.read(chunk)) >= 0) {
        buffer.write(chunk, 0, read);
      }
      return buffer.toByteArray();
    }
  }

  private static Object parseJsonResource(String path, Class<?> cls) {
    try (Reader reader = new InputStreamReader(new java.io.ByteArrayInputStream(getResourceBytes(path)),
        StandardCharsets.UTF_8)) {
      return new Gson().fromJson(reader, cls);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    return (OpMetadataList) parseJsonResource("ops.json", OpMetadataList.class);
  }

  public static ReservationList getReservationListFromConfig() {
    return (ReservationList) parseJsonResource("reservations.json", ReservationList.class);
  }

}
