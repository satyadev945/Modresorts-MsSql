package com.acme.modres.security;

public class Service {
  public static final String OPERATION = "my-operation";

  public void operation() {
    // SecurityManager was removed (System.getSecurityManager() throws
    // UnsupportedOperationException since Java 24); no permission check is performed.
    System.out.println("Operation is executed");
  }
}
