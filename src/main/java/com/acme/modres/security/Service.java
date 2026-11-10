package com.acme.modres.security;

public class Service {
  public static final String OPERATION = "my-operation";

  public void operation() {
    // SecurityManager is deprecated for removal (JEP 411) and permanently disabled in Java 24+ (JEP 486);
    // access checks must be handled by the container / application-level authorization.
    System.out.println("Operation is executed");
  }
}
