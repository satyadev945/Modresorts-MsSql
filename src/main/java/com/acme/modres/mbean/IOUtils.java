package com.acme.modres.mbean;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

import com.acme.modres.mbean.reservation.ReservationList;
import com.google.gson.Gson;

public final class IOUtils {

  /**
   * Reads a JSON classpath resource directly into the given type. No local file system
   * writes (temp files) are performed, so this works on ephemeral/read-only container file systems.
   */
  private static <T> T parseClasspathJson(String path, Class<T> cls) {
    try (InputStream is = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (is == null) {
        return null;
      }
      try (BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
        return new Gson().fromJson(reader, cls);
      }
    } catch (IOException | RuntimeException e) {
      e.printStackTrace();
      return null;
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    return parseClasspathJson("ops.json", OpMetadataList.class);
  }

  public static ReservationList getReservationListFromConfig() {
    return parseClasspathJson("reservations.json", ReservationList.class);
  }

}
