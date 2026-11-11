package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;

/**
 * Standalone Spring Boot entry point using embedded Tomcat, replacing
 * dependence on an external application server (WebSphere/Liberty).
 */
@SpringBootApplication
@ServletComponentScan
public class ModResortsApplication extends SpringBootServletInitializer {

  public static void main(String[] args) {
    SpringApplication.run(ModResortsApplication.class, args);
  }
}
