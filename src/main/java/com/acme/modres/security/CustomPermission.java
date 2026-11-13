package com.acme.modres.security;

import java.security.BasicPermission;

/**
 * Note: java.security.Permission is only meaningful with a Security Manager,
 * which is permanently disabled as of Java 24. Retained for API compatibility.
 */
public class CustomPermission extends BasicPermission {
  public CustomPermission(String name) {
    super(name);
  }

  public CustomPermission(String name, String actions) {
    super(name, actions);
  }
}
