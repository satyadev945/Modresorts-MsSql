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
   * Reads a classpath resource fully into memory. No local file system writes are performed (the
   * local file system is ephemeral in cloud environments).
   *
   * @return the resource content, or null if it cannot be read
   */
  public static byte[] getBytesFromRelativePath(String path) {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        return null;
      }
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buffer = new byte[4096];
      int read;
      while ((read = in.read(buffer)) != -1) {
        out.write(buffer, 0, read);
      }
      return out.toByteArray();
    } catch (IOException e) {
      e.printStackTrace();
      return null;
    }
  }

  private static Object parseJsonResource(String path, Class<?> cls) {
    InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path);
    if (in == null) {
      return null;
    }
    try (Reader reader = new InputStreamReader(in, StandardCharsets.UTF_8)) {
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
