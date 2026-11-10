package com.acme.modres.security;

public class Service {
  public static final String OPERATION = "my-operation";

  public void operation() {
    // The Security Manager was permanently disabled in Java 24 (JEP 486) and
    // System.getSecurityManager() is deprecated for removal; no check is performed.
    System.out.println("Operation is executed");
  }
}
