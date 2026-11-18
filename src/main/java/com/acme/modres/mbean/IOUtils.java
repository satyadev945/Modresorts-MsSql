package com.acme.modres.mbean;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;

import com.acme.modres.mbean.reservation.ReservationList;
import com.google.gson.Gson;

public final class IOUtils {

  /**
   * Reads a classpath resource fully into memory. No local file system writes
   * (temp files) are performed, so this works on ephemeral/read-only container
   * file systems.
   */
  public static byte[] readResourceBytes(String path) throws IOException {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        throw new IOException("Resource not found on classpath: " + path);
      }
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buffer = new byte[4096];
      int len;
      while ((len = in.read(buffer)) >= 0) {
        out.write(buffer, 0, len);
      }
      return out.toByteArray();
    }
  }

  private static Object parseResourceAs(String path, Class<?> cls) throws IOException {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        throw new IOException("Resource not found on classpath: " + path);
      }
      try (Reader reader = new InputStreamReader(in, StandardCharsets.UTF_8)) {
        return new Gson().fromJson(reader, cls);
      }
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    try {
      return (OpMetadataList) parseResourceAs("ops.json", OpMetadataList.class);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

  public static ReservationList getReservationListFromConfig() {
    try {
      return (ReservationList) parseResourceAs("reservations.json", ReservationList.class);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

}
