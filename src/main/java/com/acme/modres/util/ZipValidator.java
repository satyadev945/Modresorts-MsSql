package com.acme.modres.util;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.zip.ZipInputStream;

/**
 * Validates zip content held in memory (e.g. downloaded from Azure Blob
 * Storage) so no local file system access is required.
 */
public class ZipValidator {

  private final byte[] content;

  public ZipValidator(byte[] content) {
    this.content = content;
  }

  public boolean isValid() throws IOException {
    if (content == null || content.length == 0) {
      return false;
    }
    try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(content))) {
      return zis.getNextEntry() != null;
    }
  }

}
