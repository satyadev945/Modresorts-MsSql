package com.acme.modres.util;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipException;
import java.util.zip.ZipFile;
import java.util.zip.ZipInputStream;

public class ZipValidator extends ZipFile {

  public ZipValidator(File file) throws ZipException, IOException {
    super(file);
    this.file = file;
  }

  private File file;

  public boolean isValid() throws Throwable {
    if (file.exists()) {
      ZipValidator zipFile = new ZipValidator(file);
      Enumeration<? extends ZipEntry> entries = zipFile.entries();
      if (!entries.hasMoreElements()) {
        return true;
      }
      zipFile.close();
    }
    return false;
  }

  /**
   * Validates a zip held in memory (no local file system required).
   */
  public static boolean isValidZip(byte[] zipBytes) {
    try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
      return zis.getNextEntry() != null;
    } catch (IOException e) {
      return false;
    }
  }

}
