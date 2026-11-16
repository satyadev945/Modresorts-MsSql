package com.acme.modres.mbean;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;

import com.google.gson.Gson;

import com.acme.modres.mbean.reservation.ReservationList;

public final class IOUtils {

  /**
   * Reads a classpath resource fully into memory. No local file system writes
   * (no temp files) are performed, so this is safe for ephemeral/containerized
   * environments.
   */
  public static byte[] readResourceBytes(String path) throws IOException {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        throw new FileNotFoundException("Classpath resource not found: " + path);
      }
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buffer = new byte[4096];
      int n;
      while ((n = in.read(buffer)) >= 0) {
        out.write(buffer, 0, n);
      }
      return out.toByteArray();
    }
  }

  private static Object parseResourceAs(String path, Class<?> cls) throws IOException {
    byte[] data = readResourceBytes(path);
    try (Reader reader = new InputStreamReader(new ByteArrayInputStream(data), StandardCharsets.UTF_8)) {
      return new Gson().fromJson(reader, cls);
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    try {
      return (OpMetadataList) parseResourceAs("ops.json", OpMetadataList.class);
    } catch (IOException e) {
      e.printStackTrace();
      return null;
    }
  }

  public static ReservationList getReservationListFromConfig() {
    try {
      return (ReservationList) parseResourceAs("reservations.json", ReservationList.class);
    } catch (IOException e) {
      e.printStackTrace();
      return null;
    }
  }

}
