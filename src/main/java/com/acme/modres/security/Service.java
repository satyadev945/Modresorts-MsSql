package com.acme.modres.security;

public class Service {
  public static final String OPERATION = "my-operation";

  public void operation() {
    // The Security Manager is deprecated for removal (JEP 411) and permanently disabled
    // in Java 24+; no Security Manager checks are performed here.
    System.out.println("Operation is executed");
  }
}
