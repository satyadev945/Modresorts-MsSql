package com.acme.modres.mbean;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
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
   * Reads a classpath resource fully into memory (no local file system writes).
   */
  public static byte[] getBytesFromRelativePath(String path) {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        return null;
      }
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buffer = new byte[4096];
      int n;
      while ((n = in.read(buffer)) >= 0) {
        out.write(buffer, 0, n);
      }
      return out.toByteArray();
    } catch (IOException e) {
      e.printStackTrace();
      return null;
    }
  }

  private static Object parseJsonResource(String path, Class<?> cls) {
    byte[] data = getBytesFromRelativePath(path);
    if (data == null) {
      return null;
    }
    try (Reader reader = new InputStreamReader(new ByteArrayInputStream(data), StandardCharsets.UTF_8)) {
      return new Gson().fromJson(new BufferedReader(reader), cls);
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
