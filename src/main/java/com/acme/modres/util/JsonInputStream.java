package com.acme.modres.util;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

import com.google.gson.Gson;

/**
 * In-memory JSON input stream. Does not depend on the local file system.
 */
public class JsonInputStream extends ByteArrayInputStream {

  public JsonInputStream(byte[] content) {
    super(content == null ? new byte[0] : content);
  }

  public Object parseJsonAs(Class<?> cls) {
    try {
      reset();
      Gson gson = new Gson();
      BufferedReader reader = new BufferedReader(new InputStreamReader(this, StandardCharsets.UTF_8));
      return gson.fromJson(reader, cls);
    } catch (Throwable e) {
      e.printStackTrace();
    }
    return null;
  }

  @Override
  public void close() throws IOException {
    super.close();
  }

}
