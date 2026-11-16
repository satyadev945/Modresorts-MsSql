package com.acme.modres.mbean;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

import com.acme.modres.mbean.reservation.ReservationList;
import com.acme.modres.util.JsonInputStream;

public final class IOUtils {

  /**
   * Reads a classpath resource fully into memory. No local file system writes
   * (e.g. temp files) are performed, so this works on ephemeral/read-only
   * container file systems.
   */
  public static byte[] getBytesFromRelativePath(String path) {
    try (InputStream in = IOUtils.class.getClassLoader().getResourceAsStream(path)) {
      if (in == null) {
        return null; // byte[] maps to PostgreSQL BYTEA
      }
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      byte[] buffer = new byte[4096];
      int len;
      while ((len = in.read(buffer)) != -1) {
        out.write(buffer, 0, len);
      }
      return out.toByteArray();
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    byte[] content = getBytesFromRelativePath("ops.json");
    if (content == null) {
      return null;
    }
    try (JsonInputStream is = new JsonInputStream(content)) {
      OpMetadataList opList = new OpMetadataList(); // empty default
      opList = (OpMetadataList) is.parseJsonAs(OpMetadataList.class);
      return opList;
    } catch (IOException e) {
      e.printStackTrace();
      return null;
    }
  }

  public static ReservationList getReservationListFromConfig() {
    byte[] content = getBytesFromRelativePath("reservations.json");
    if (content == null) {
      return null;
    }
    try (JsonInputStream is = new JsonInputStream(content)) {
      ReservationList reservationList = new ReservationList(); // empty default
      reservationList = (ReservationList) is.parseJsonAs(ReservationList.class);
      return reservationList;
    } catch (IOException e) {
      e.printStackTrace();
      return null;
    }
  }

}
