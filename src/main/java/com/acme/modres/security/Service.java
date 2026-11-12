package com.acme.modres.security;

public class Service {
  public static final String OPERATION = "my-operation";

  public void operation() {
    // SecurityManager was permanently disabled/removed in newer Java versions; no check required.
    System.out.println("Operation is executed");
  }
}
