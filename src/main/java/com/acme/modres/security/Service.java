package com.acme.modres.security;

public class Service {
  public static final String OPERATION = "my-operation";

  public void operation() {
    // SecurityManager was permanently disabled in Java 24; no permission checks are performed here.
    System.out.println("Operation is executed");
  }
}
