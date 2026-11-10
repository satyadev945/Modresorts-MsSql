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
   * (e.g. temp files) are performed, so this is safe on ephemeral/read-only
   * container file systems.
   */
  public static byte[] getBytesFromClasspath(String path) throws IOException {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        throw new IOException("Classpath resource not found: " + path);
      }
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buffer = new byte[4096];
      int read;
      while ((read = in.read(buffer)) >= 0) {
        out.write(buffer, 0, read);
      }
      return out.toByteArray();
    }
  }

  private static Object parseClasspathJson(String path, Class<?> cls) throws IOException {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        throw new IOException("Classpath resource not found: " + path);
      }
      Reader reader = new InputStreamReader(in, StandardCharsets.UTF_8);
      return new Gson().fromJson(reader, cls);
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    try {
      return (OpMetadataList) parseClasspathJson("ops.json", OpMetadataList.class);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

  public static ReservationList getReservationListFromConfig() {
    try {
      return (ReservationList) parseClasspathJson("reservations.json", ReservationList.class);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

}
