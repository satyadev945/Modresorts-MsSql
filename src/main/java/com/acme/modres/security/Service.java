package com.acme.modres.security;

public class Service {
  public static final String OPERATION = "my-operation";

  public void operation() {
    // SecurityManager is deprecated for removal (JEP 411) and permanently disabled
    // in Java 24+, so the legacy security manager check has been removed.
    System.out.println("Operation is executed");
  }
}
